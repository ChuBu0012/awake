package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"awake/internal/domain"
)

var (
	ErrCorruptState = errors.New("Awake state file is corrupt or unsupported")
	ErrLockTimeout  = errors.New("timed out waiting for the Awake state lock")
	ErrUnsafePath   = errors.New("Awake state path is not private and user-owned")
	ErrInvalidState = errors.New("Awake state violates the schema")
)

const lockWaitLimit = 5 * time.Second

type Store struct {
	dir string
}

// Open creates or validates a private, user-owned state directory.
func Open(dir string) (*Store, error) {
	if !filepath.IsAbs(dir) {
		return nil, fmt.Errorf("state directory must be absolute: %w", ErrUnsafePath)
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, fmt.Errorf("create state directory: %w", err)
	}
	info, err := os.Lstat(dir)
	if err != nil {
		return nil, fmt.Errorf("inspect state directory: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() || !ownedByCurrentUser(info) {
		return nil, ErrUnsafePath
	}
	if err := os.Chmod(dir, 0o700); err != nil {
		return nil, fmt.Errorf("secure state directory: %w", err)
	}
	return &Store{dir: filepath.Clean(dir)}, nil
}

// DefaultDirectory resolves the same private state path for the Go CLI and
// the Swift menu-bar app. Non-absolute XDG_CONFIG_HOME values are ignored.
func DefaultDirectory(home, xdgConfigHome string) (string, error) {
	if home == "" || !filepath.IsAbs(home) {
		return "", fmt.Errorf("home directory must be absolute")
	}
	base := xdgConfigHome
	if !filepath.IsAbs(base) {
		base = filepath.Join(home, ".config")
	}
	return filepath.Join(base, "awake"), nil
}

func (s *Store) Read() (domain.State, error) {
	path := filepath.Join(s.dir, "state.json")
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return defaultState(), nil
	}
	if err != nil {
		return domain.State{}, fmt.Errorf("inspect Awake state: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || !ownedByCurrentUser(info) {
		return domain.State{}, ErrUnsafePath
	}
	if info.Mode().Perm()&0o077 != 0 {
		if err := os.Chmod(path, 0o600); err != nil {
			return domain.State{}, fmt.Errorf("secure Awake state file: %w", err)
		}
	}
	file, err := os.Open(path)
	if err != nil {
		return domain.State{}, fmt.Errorf("open Awake state: %w", err)
	}
	defer file.Close()

	data, err := io.ReadAll(io.LimitReader(file, 1<<20))
	if err != nil {
		return domain.State{}, fmt.Errorf("read Awake state: %w", err)
	}
	state, err := decodeState(data)
	if err != nil {
		return domain.State{}, err
	}
	if err := validate(state); err != nil {
		return domain.State{}, fmt.Errorf("%w: %v", ErrCorruptState, err)
	}
	return state, nil
}

// Update serializes a read-modify-write transaction and publishes it with an
// atomic rename. A failed callback or invalid state leaves the old file intact.
func (s *Store) Update(ctx context.Context, mutate func(*domain.State) error) error {
	if mutate == nil {
		return fmt.Errorf("state mutation is required")
	}
	return s.Transact(ctx, func(state *domain.State, _ func() error) error {
		return mutate(state)
	})
}

// Transact holds the interprocess lock while reading, mutating, and reconciling
// state. The callback may call save before a system-wide side effect so the
// recovery journal is durable before that side effect begins.
func (s *Store) Transact(ctx context.Context, apply func(*domain.State, func() error) error) error {
	if apply == nil {
		return fmt.Errorf("state transaction is required")
	}
	lock, err := acquireLock(ctx, filepath.Join(s.dir, "state.lock"), lockWaitLimit)
	if err != nil {
		return err
	}
	defer lock.Close()

	state, err := s.Read()
	if err != nil {
		return err
	}
	migrationRequired := state.MigrationRequired
	state.MigrationRequired = false
	lastSaved, _ := json.Marshal(state)
	if migrationRequired {
		lastSaved = nil
	}
	save := func() error {
		if state.SchemaVersion == 0 {
			state.SchemaVersion = domain.CurrentSchemaVersion
		}
		if err := validate(state); err != nil {
			return fmt.Errorf("%w: %v", ErrInvalidState, err)
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := s.writeAtomic(state); err != nil {
			return err
		}
		lastSaved, _ = json.Marshal(state)
		return nil
	}
	if err := apply(&state, save); err != nil {
		return err
	}
	current, _ := json.Marshal(state)
	if string(current) == string(lastSaved) {
		return nil
	}
	return save()
}

func (s *Store) writeAtomic(state domain.State) error {
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("encode Awake state: %w", err)
	}
	data = append(data, '\n')
	file, err := os.CreateTemp(s.dir, ".state-*.tmp")
	if err != nil {
		return fmt.Errorf("create temporary Awake state: %w", err)
	}
	tempPath := file.Name()
	defer os.Remove(tempPath)
	if err := file.Chmod(0o600); err != nil {
		file.Close()
		return fmt.Errorf("secure temporary Awake state: %w", err)
	}
	if _, err := file.Write(data); err != nil {
		file.Close()
		return fmt.Errorf("write Awake state: %w", err)
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return fmt.Errorf("flush Awake state: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close Awake state: %w", err)
	}
	if err := os.Rename(tempPath, filepath.Join(s.dir, "state.json")); err != nil {
		return fmt.Errorf("publish Awake state: %w", err)
	}
	directory, err := os.Open(s.dir)
	if err != nil {
		return fmt.Errorf("open state directory for sync: %w", err)
	}
	defer directory.Close()
	if err := directory.Sync(); err != nil {
		return fmt.Errorf("flush state directory: %w", err)
	}
	return nil
}

func decodeState(data []byte) (domain.State, error) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil || fields == nil {
		if err == nil {
			err = fmt.Errorf("state must be a JSON object")
		}
		return domain.State{}, fmt.Errorf("%w: %v", ErrCorruptState, err)
	}
	if _, versioned := fields["schema_version"]; !versioned {
		return migrateLegacyState(data)
	}
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	var state domain.State
	if err := decoder.Decode(&state); err != nil {
		return domain.State{}, fmt.Errorf("%w: %v", ErrCorruptState, err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return domain.State{}, fmt.Errorf("%w: trailing JSON data", ErrCorruptState)
	}
	return state, nil
}

func migrateLegacyState(data []byte) (domain.State, error) {
	var legacy struct {
		Active                *bool `json:"active"`
		ExpiresAt             int64 `json:"expires_at"`
		CaffeinatePID         int   `json:"caffeinate_pid"`
		PreviousSleepDisabled *int  `json:"previous_sleep_disabled"`
	}
	if err := json.Unmarshal(data, &legacy); err != nil || legacy.Active == nil {
		if err == nil {
			err = fmt.Errorf("unrecognized legacy state")
		}
		return domain.State{}, fmt.Errorf("%w: %v", ErrCorruptState, err)
	}
	state := domain.State{SchemaVersion: domain.CurrentSchemaVersion, BatteryGuardEnabled: true, MigrationRequired: true}
	if legacy.PreviousSleepDisabled != nil {
		if *legacy.PreviousSleepDisabled != 0 && *legacy.PreviousSleepDisabled != 1 {
			return domain.State{}, fmt.Errorf("%w: invalid legacy SleepDisabled baseline", ErrCorruptState)
		}
		baseline := *legacy.PreviousSleepDisabled == 1
		state.SleepDisabledBaseline = &baseline
		state.LidSupportEnabled = *legacy.Active
		if !baseline {
			applied := true
			state.SleepDisabledApplied = &applied
		}
	} else if *legacy.Active {
		state.RecoveryWarning = "Previous state did not record the original SleepDisabled value; Awake will not guess a restoration value."
	}
	if *legacy.Active {
		lease := domain.Lease{ID: "manual", Source: domain.SourceManual, Reason: "Migrated manual Awake request"}
		if legacy.ExpiresAt > 0 {
			lease.ExpiresAt = time.Unix(legacy.ExpiresAt, 0)
		}
		state.Leases = append(state.Leases, lease)
	}
	if legacy.CaffeinatePID > 1 {
		pid := legacy.CaffeinatePID
		state.LegacyAssertionPID = &pid
	}
	return state, nil
}

func defaultState() domain.State {
	return domain.State{SchemaVersion: domain.CurrentSchemaVersion, BatteryGuardEnabled: true}
}

func validate(state domain.State) error {
	if state.SchemaVersion != domain.CurrentSchemaVersion {
		return fmt.Errorf("unsupported schema version %d", state.SchemaVersion)
	}
	seen := make(map[string]struct{}, len(state.Leases)+len(state.Rules))
	for _, lease := range state.Leases {
		if strings.TrimSpace(lease.ID) == "" || !validSource(lease.Source) {
			return fmt.Errorf("lease requires an ID and supported source")
		}
		if _, exists := seen[lease.ID]; exists {
			return fmt.Errorf("duplicate lease or rule ID %q", lease.ID)
		}
		seen[lease.ID] = struct{}{}
	}
	for _, rule := range state.Rules {
		if strings.TrimSpace(rule.ID) == "" || !validRule(rule) {
			return fmt.Errorf("rule %q has invalid fields", rule.ID)
		}
		if _, exists := seen[rule.ID]; exists {
			return fmt.Errorf("duplicate lease or rule ID %q", rule.ID)
		}
		seen[rule.ID] = struct{}{}
	}
	return nil
}

func validSource(source domain.Source) bool {
	switch source {
	case domain.SourceManual, domain.SourceCommand, domain.SourceActivity, domain.SourceSchedule:
		return true
	default:
		return false
	}
}

func validRule(rule domain.Rule) bool {
	switch rule.Kind {
	case domain.RuleAppOpen:
		return rule.BundleID != ""
	case domain.RuleWorkProcess:
		return len(rule.ProcessNames) > 0
	case domain.RuleSchedule:
		if rule.StartMinute < 0 || rule.StartMinute >= 24*60 || rule.EndMinute < 0 || rule.EndMinute >= 24*60 || rule.StartMinute == rule.EndMinute || len(rule.Weekdays) == 0 {
			return false
		}
		for _, day := range rule.Weekdays {
			if day < time.Sunday || day > time.Saturday {
				return false
			}
		}
		return true
	default:
		return false
	}
}
