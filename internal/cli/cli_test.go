package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"awake/internal/domain"
	"awake/internal/engine"
	"awake/internal/store"
)

func TestRunPassesArgumentsWithoutShellAndReleasesOnlyItsLease(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	adapter := &fakeAdapter{running: make(map[string]domain.ProcessID), now: now}
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	coordinator := engine.New(stateStore, adapter, func() time.Time { return now })
	runner := &fakeCommandRunner{exitCode: 0}
	var stdout, stderr bytes.Buffer
	app := New(coordinator, adapter, runner, &stdout, &stderr)

	command := []string{"printf", "hello; pmset -a disablesleep 1"}
	if err := app.Run(context.Background(), append([]string{"run"}, command...)); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(runner.args, command) {
		t.Fatalf("child arguments = %#v, want %#v without shell rewriting", runner.args, command)
	}
	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if len(state.Leases) != 0 {
		t.Fatalf("run lease remained after command returned: %#v", state.Leases)
	}
	if len(adapter.running) != 0 {
		t.Fatalf("run assertion remained after command returned: %#v", adapter.running)
	}
}

func TestRunRequiresCommand(t *testing.T) {
	adapter := &fakeAdapter{running: make(map[string]domain.ProcessID), now: time.Now()}
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	app := New(engine.New(stateStore, adapter, time.Now), adapter, &fakeCommandRunner{}, &bytes.Buffer{}, &bytes.Buffer{})
	if err := app.Run(context.Background(), []string{"run"}); err == nil {
		t.Fatal("run without a child command unexpectedly succeeded")
	}
}

func TestRecoverPreservesLiveAutomationOwner(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	adapter := &fakeAdapter{running: make(map[string]domain.ProcessID), now: now}
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	coordinator := engine.New(stateStore, adapter, func() time.Time { return now })
	owner := domain.ProcessID{PID: 42, StartTime: "current", BootID: "boot"}
	if err := coordinator.SetAutomationOwner(context.Background(), owner); err != nil {
		t.Fatal(err)
	}
	if err := coordinator.SetRule(context.Background(), domain.Rule{ID: "editor", Kind: domain.RuleAppOpen, Enabled: true, BundleID: "com.example.editor"}); err != nil {
		t.Fatal(err)
	}
	if _, err := coordinator.Tick(context.Background(), domain.Observation{OpenBundleIDs: []string{"com.example.editor"}}); err != nil {
		t.Fatal(err)
	}
	app := New(coordinator, adapter, &fakeCommandRunner{}, &bytes.Buffer{}, &bytes.Buffer{})
	if err := app.Run(context.Background(), []string{"recover"}); err != nil {
		t.Fatal(err)
	}
	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if state.AutomationOwner == nil || state.AutomationOwner.PID != 42 {
		t.Fatalf("recover cleared the live automation owner: %#v", state.AutomationOwner)
	}
}

func TestSetupRunsExactInstalledHelperPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "setup-sudoers.sh")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nexit 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("AWAKE_SETUP_SCRIPT", path)
	adapter := &fakeAdapter{running: make(map[string]domain.ProcessID), now: time.Now()}
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	runner := &fakeCommandRunner{}
	app := New(engine.New(stateStore, adapter, time.Now), adapter, runner, &bytes.Buffer{}, &bytes.Buffer{})
	if err := app.Run(context.Background(), []string{"setup"}); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(runner.args, []string{path}) {
		t.Fatalf("setup helper invocation = %#v, want exact path as one argv", runner.args)
	}
}

func TestStatusJSONUsesEmptyArraysForNoRequestsOrRules(t *testing.T) {
	data, err := json.Marshal(statusFrom(domain.State{}, domain.Evaluation{}))
	if err != nil {
		t.Fatal(err)
	}
	var result map[string]json.RawMessage
	if err := json.Unmarshal(data, &result); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"requests", "rules"} {
		var values []json.RawMessage
		if err := json.Unmarshal(result[key], &values); err != nil {
			t.Fatalf("%s must be a JSON array, got %s: %v", key, result[key], err)
		}
		if values == nil {
			t.Fatalf("%s must be [] rather than null", key)
		}
	}
}

type fakeAdapter struct {
	running map[string]domain.ProcessID
	now     time.Time
	nextPID int
}

func (f *fakeAdapter) ReadPower(context.Context) (domain.PowerState, error) {
	return domain.PowerState{OnAC: true, BatteryPercent: 100, BatteryKnown: true}, nil
}

func (f *fakeAdapter) Observe(context.Context) (domain.Observation, error) {
	return domain.Observation{}, nil
}

func (f *fakeAdapter) ProcessIdentity(_ context.Context, pid int) (domain.ProcessID, string, error) {
	return domain.ProcessID{PID: pid, StartTime: "current", BootID: "boot"}, "awake", nil
}

func (f *fakeAdapter) ProcessAlive(id domain.ProcessID) bool {
	if id.StartTime == "current" && id.BootID == "boot" {
		return true
	}
	for _, process := range f.running {
		if process == id {
			return true
		}
	}
	return false
}

func (f *fakeAdapter) StartAssertion(_ context.Context, requestID string, _ *domain.ProcessID) (domain.ProcessID, error) {
	f.nextPID++
	id := domain.ProcessID{PID: 1000 + f.nextPID, StartTime: f.now.String(), BootID: "boot"}
	f.running[requestID] = id
	return id, nil
}

func (f *fakeAdapter) StopAssertion(id domain.ProcessID) error {
	for key, process := range f.running {
		if process == id {
			delete(f.running, key)
		}
	}
	return nil
}

func (f *fakeAdapter) ReadSleepDisabled(context.Context) (bool, error) { return false, nil }
func (f *fakeAdapter) SetSleepDisabled(context.Context, bool) error    { return nil }

type fakeCommandRunner struct {
	args     []string
	exitCode int
}

func (f *fakeCommandRunner) Run(_ context.Context, args []string) (int, error) {
	f.args = append([]string(nil), args...)
	return f.exitCode, nil
}

func TestValidProcessName(t *testing.T) {
	valid := []string{
		"node",
		"swift-frontend",
		"Code Helper",
		"Code Helper (Renderer)",
		"Code Helper (Plugin)",
		"Google Chrome Helper",
		"cursor_daemon+v1",
		"my-proc.bin",
	}
	for _, name := range valid {
		if !validProcessName(name) {
			t.Errorf("validProcessName(%q) = false, want true", name)
		}
	}

	invalid := []string{
		"",
		"   ",
		" Code Helper",
		"Code Helper ",
		"/bin/sh",
		"../proc",
		".",
		"..",
		"proc\nname",
		"rm -rf *",
		"foo;bar",
		"foo|bar",
		"foo`bar`",
		"foo$bar",
	}
	for _, name := range invalid {
		if validProcessName(name) {
			t.Errorf("validProcessName(%q) = true, want false", name)
		}
	}
}

func TestRuleProcessAllowsProcessNameWithSpaces(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	adapter := &fakeAdapter{running: make(map[string]domain.ProcessID), now: now}
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	coordinator := engine.New(stateStore, adapter, func() time.Time { return now })
	runner := &fakeCommandRunner{exitCode: 0}
	app := New(coordinator, adapter, runner, &bytes.Buffer{}, &bytes.Buffer{})

	err = app.Run(context.Background(), []string{"rule", "process", "proc-1", "Visual Studio Code", "Code Helper"})
	if err != nil {
		t.Fatalf("rule process with spaces failed: %v", err)
	}
	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if len(state.Rules) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(state.Rules))
	}
	rule := state.Rules[0]
	if rule.Name != "Visual Studio Code" || len(rule.ProcessNames) != 1 || rule.ProcessNames[0] != "Code Helper" {
		t.Fatalf("unexpected rule contents: %+v", rule)
	}
}
