package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"awake/internal/domain"
)

func TestOpenCreatesPrivateStateDirectoryAndDefaults(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "awake")
	stateStore, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}

	info, err := os.Stat(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != 0o700 {
		t.Fatalf("state directory mode = %#o, want 0700", got)
	}

	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if state.SchemaVersion != domain.CurrentSchemaVersion || !state.BatteryGuardEnabled {
		t.Fatalf("initial state = %#v, want current schema and battery guard enabled", state)
	}
}

func TestUpdateSerializesConcurrentMutations(t *testing.T) {
	stateStore, err := Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}

	const writers = 48
	var wait sync.WaitGroup
	wait.Add(writers)
	errorsByWriter := make(chan error, writers)
	for i := 0; i < writers; i++ {
		go func(i int) {
			defer wait.Done()
			err := stateStore.Update(context.Background(), func(state *domain.State) error {
				state.Leases = append(state.Leases, domain.Lease{ID: fmt.Sprintf("lease-%02d", i), Source: domain.SourceCommand})
				return nil
			})
			errorsByWriter <- err
		}(i)
	}
	wait.Wait()
	close(errorsByWriter)
	for err := range errorsByWriter {
		if err != nil {
			t.Fatal(err)
		}
	}

	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if got := len(state.Leases); got != writers {
		t.Fatalf("persisted lease count = %d, want %d", got, writers)
	}
}

func TestCorruptStateIsPreservedAndNeverReplaced(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "awake")
	if err := os.Mkdir(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "state.json")
	corrupt := []byte(`{"schema_version":`)
	if err := os.WriteFile(path, corrupt, 0o600); err != nil {
		t.Fatal(err)
	}
	stateStore, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}

	_, readErr := stateStore.Read()
	if !errors.Is(readErr, ErrCorruptState) {
		t.Fatalf("Read error = %v, want ErrCorruptState", readErr)
	}
	updateErr := stateStore.Update(context.Background(), func(state *domain.State) error { return nil })
	if !errors.Is(updateErr, ErrCorruptState) {
		t.Fatalf("Update error = %v, want ErrCorruptState", updateErr)
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(corrupt) {
		t.Fatalf("corrupt state changed: got %q, want original %q", after, corrupt)
	}
}

func TestUpdateWritesPrivateValidJSON(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "awake")
	stateStore, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	err = stateStore.Update(context.Background(), func(state *domain.State) error {
		state.Leases = []domain.Lease{{ID: "run", Source: domain.SourceCommand, ExpiresAt: time.Now().Add(time.Hour)}}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	path := filepath.Join(dir, "state.json")
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Fatalf("state file mode = %#o, want 0600", got)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var decoded domain.State
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("state file is invalid JSON: %v", err)
	}
}

func TestStateRoundTripsIndependentAssertionsAndRecoveryJournal(t *testing.T) {
	stateStore, err := Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	baseline := false
	applied := true
	err = stateStore.Update(context.Background(), func(state *domain.State) error {
		state.LidSupportEnabled = true
		state.SleepDisabledBaseline = &baseline
		state.SleepDisabledApplied = &applied
		state.Assertions = map[string]domain.ProcessID{
			"run:one": {PID: 812, StartTime: "Fri Nov 20 10:00:00 2026", BootID: "boot-a"},
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if !state.LidSupportEnabled || state.SleepDisabledBaseline == nil || *state.SleepDisabledBaseline || state.SleepDisabledApplied == nil || !*state.SleepDisabledApplied {
		t.Fatalf("recovery journal did not round-trip: %#v", state)
	}
	if got := state.Assertions["run:one"]; got.PID != 812 || got.StartTime == "" || got.BootID != "boot-a" {
		t.Fatalf("assertion identity = %#v, want recorded process identity", got)
	}
}

func TestTransactionCanPersistRecoveryJournalBeforeFailingSystemAction(t *testing.T) {
	stateStore, err := Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	baseline := false
	actionErr := errors.New("simulated pmset failure")
	err = stateStore.Transact(context.Background(), func(state *domain.State, save func() error) error {
		state.SleepDisabledBaseline = &baseline
		if err := save(); err != nil {
			return err
		}
		return actionErr
	})
	if !errors.Is(err, actionErr) {
		t.Fatalf("Transact error = %v, want simulated action error", err)
	}
	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if state.SleepDisabledBaseline == nil || *state.SleepDisabledBaseline {
		t.Fatalf("pre-action recovery journal = %#v, want saved original false value", state.SleepDisabledBaseline)
	}
}

func TestLegacyCLIStateMigratesBaselineLeaseAndAssertionPID(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "awake")
	if err := os.Mkdir(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "state.json")
	legacy := []byte(`{"active":true,"started_at":1795212000,"duration_seconds":0,"expires_at":0,"caffeinate_pid":812,"mode":"manual","previous_sleep_disabled":0}`)
	if err := os.WriteFile(path, legacy, 0o600); err != nil {
		t.Fatal(err)
	}
	stateStore, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if state.SchemaVersion != domain.CurrentSchemaVersion || len(state.Leases) != 1 || state.Leases[0].ID != "manual" {
		t.Fatalf("legacy request migration = %#v", state)
	}
	if state.SleepDisabledBaseline == nil || *state.SleepDisabledBaseline || state.SleepDisabledApplied == nil || !*state.SleepDisabledApplied || state.LegacyAssertionPID == nil || *state.LegacyAssertionPID != 812 {
		t.Fatalf("legacy recovery migration = %#v", state)
	}
	if err := stateStore.Update(context.Background(), func(*domain.State) error { return nil }); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var versioned map[string]any
	if err := json.Unmarshal(data, &versioned); err != nil {
		t.Fatal(err)
	}
	if versioned["schema_version"] != float64(domain.CurrentSchemaVersion) {
		t.Fatalf("state was not atomically upgraded: %#v", versioned)
	}
}

func TestLegacyStateWithoutBaselineIsMarkedForManualRecovery(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "awake")
	if err := os.Mkdir(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "state.json"), []byte(`{"active":true,"expires_at":0}`), 0o600); err != nil {
		t.Fatal(err)
	}
	stateStore, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if state.RecoveryWarning == "" || state.LidSupportEnabled {
		t.Fatalf("legacy state without baseline should not guess a system value: %#v", state)
	}
}
