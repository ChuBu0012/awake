package engine

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"awake/internal/domain"
	"awake/internal/store"
)

func TestManualOffClearsManualWhileAutomationContinues(t *testing.T) {
	now := time.Date(2026, time.November, 20, 23, 0, 0, 0, time.UTC)
	adapter := newFakeAdapter(now)
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	coordinator := New(stateStore, adapter, func() time.Time { return now })

	if err := coordinator.SetRule(context.Background(), domain.Rule{ID: "agent", Kind: domain.RuleWorkProcess, Enabled: true, ProcessNames: []string{"agentd"}}); err != nil {
		t.Fatal(err)
	}
	if err := coordinator.SetAutomationOwner(context.Background(), domain.ProcessID{PID: 42, StartTime: "menu-app", BootID: "boot"}); err != nil {
		t.Fatal(err)
	}
	adapter.observation.Processes = []domain.Process{{Name: "agentd"}}
	if err := coordinator.AddLease(context.Background(), domain.Lease{ID: "run-1", Source: domain.SourceCommand}); err != nil {
		t.Fatal(err)
	}
	if err := coordinator.ActivateManual(context.Background(), 0, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := coordinator.Tick(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := coordinator.Off(context.Background()); err != nil {
		t.Fatal(err)
	}
	result, err := coordinator.Tick(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	if !result.Effective || len(result.Requests) != 2 {
		t.Fatalf("post-Off result = %#v, want command lease and automation to remain effective", result)
	}
	if _, exists := adapter.running["rule:agent"]; !exists {
		t.Fatal("manual Off unexpectedly stopped the active automation rule")
	}
	if _, exists := adapter.running["run-1"]; !exists {
		t.Fatal("manual Off stopped the explicit command assertion")
	}
	for _, req := range result.Requests {
		if req.Source == domain.SourceManual {
			t.Fatal("manual Off failed to clear the manual lease")
		}
	}
}

func TestEndSessionClearsManualAndAutomationWithoutStartingSnooze(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	adapter := newFakeAdapter(now)
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	coordinator := New(stateStore, adapter, func() time.Time { return now })
	if err := coordinator.ActivateManual(context.Background(), 0, nil); err != nil {
		t.Fatal(err)
	}
	if err := coordinator.AddLease(context.Background(), domain.Lease{ID: "run", Source: domain.SourceCommand}); err != nil {
		t.Fatal(err)
	}
	if err := coordinator.SetAutomationOwner(context.Background(), domain.ProcessID{PID: 42, StartTime: "menu-app", BootID: "boot"}); err != nil {
		t.Fatal(err)
	}
	if err := coordinator.EndSession(context.Background()); err != nil {
		t.Fatal(err)
	}
	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if state.AutomationOwner != nil || len(state.Leases) != 1 || state.Leases[0].Source != domain.SourceCommand || !state.SnoozeUntil.IsZero() {
		t.Fatalf("session end state = %#v, want only command lease and no new snooze", state)
	}
}

func TestBatteryGuardKeepsLeaseAndStopsItsAssertion(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	adapter := newFakeAdapter(now)
	adapter.power = domain.PowerState{OnAC: true, BatteryPercent: 90}
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	coordinator := New(stateStore, adapter, func() time.Time { return now })
	if err := coordinator.AddLease(context.Background(), domain.Lease{ID: "run-2", Source: domain.SourceCommand}); err != nil {
		t.Fatal(err)
	}
	if _, err := coordinator.Tick(context.Background()); err != nil {
		t.Fatal(err)
	}
	adapter.power = domain.PowerState{OnAC: false, BatteryPercent: 20}
	result, err := coordinator.Tick(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	if result.Effective || !result.BatterySuppressed || len(result.Requests) != 1 {
		t.Fatalf("battery guard result = %#v, want preserved request with suppressed assertion", result)
	}
	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if len(state.Leases) != 1 || state.Leases[0].ID != "run-2" {
		t.Fatalf("battery guard removed lease: %#v", state.Leases)
	}
	if len(adapter.running) != 0 {
		t.Fatalf("battery guard left assertions running: %#v", adapter.running)
	}
}

func TestTickWithoutFreshBundleObservationPreservesLastAppObservation(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	adapter := newFakeAdapter(now)
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	coordinator := New(stateStore, adapter, func() time.Time { return now })
	if err := coordinator.SetAutomationOwner(context.Background(), domain.ProcessID{PID: 42, StartTime: "menu-app", BootID: "boot"}); err != nil {
		t.Fatal(err)
	}
	if err := coordinator.SetRule(context.Background(), domain.Rule{ID: "editor", Kind: domain.RuleAppOpen, Enabled: true, BundleID: "com.example.editor"}); err != nil {
		t.Fatal(err)
	}
	first, err := coordinator.Tick(context.Background(), domain.Observation{OpenBundleIDs: []string{"com.example.editor"}})
	if err != nil {
		t.Fatal(err)
	}
	if !first.Effective {
		t.Fatal("matching app observation did not activate the rule")
	}

	second, err := coordinator.Tick(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !second.Effective || len(second.Requests) != 1 || second.Requests[0].ID != "rule:editor" {
		t.Fatalf("tick without bundle input lost the previous observation: %#v", second)
	}
}

func TestLidSettingRestoresCapturedValueAfterLastRequest(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	adapter := newFakeAdapter(now)
	adapter.sleepDisabled = false
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	coordinator := New(stateStore, adapter, func() time.Time { return now })
	if err := coordinator.SetLidSupport(context.Background(), true); err != nil {
		t.Fatal(err)
	}
	if err := coordinator.AddLease(context.Background(), domain.Lease{ID: "manual-1", Source: domain.SourceManual}); err != nil {
		t.Fatal(err)
	}
	if _, err := coordinator.Tick(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !adapter.sleepDisabled {
		t.Fatal("lid support did not apply disablesleep while request was active")
	}
	if err := coordinator.Release(context.Background(), "manual-1"); err != nil {
		t.Fatal(err)
	}
	if _, err := coordinator.Tick(context.Background()); err != nil {
		t.Fatal(err)
	}
	if adapter.sleepDisabled {
		t.Fatal("lid support did not restore the original disablesleep=false value")
	}
	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if state.SleepDisabledBaseline != nil || state.SleepDisabledApplied != nil {
		t.Fatalf("recovery journal remains after successful restore: %#v", state)
	}
}

func TestLidSetupFailureFallsBackToIdleAssertion(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	adapter := newFakeAdapter(now)
	adapter.setSleepErr = errors.New("sudoers rule is missing")
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	coordinator := New(stateStore, adapter, func() time.Time { return now })
	if err := coordinator.SetLidSupport(context.Background(), true); err != nil {
		t.Fatal(err)
	}
	if err := coordinator.AddLease(context.Background(), domain.Lease{ID: "manual-1", Source: domain.SourceManual}); err != nil {
		t.Fatal(err)
	}

	result, err := coordinator.Tick(context.Background())
	if err != nil {
		t.Fatalf("Tick returned error on optional lid failure: %v", err)
	}
	if !result.Effective {
		t.Fatal("assertion should remain effective with standard caffeinate")
	}
	if _, exists := adapter.running["manual-1"]; !exists {
		t.Fatal("failed optional lid setup stopped the user-space idle assertion")
	}
	state, err := stateStore.Read()
	if err != nil {
		t.Fatal(err)
	}
	if state.SleepDisabledBaseline != nil || state.SleepDisabledApplied != nil {
		t.Fatalf("failed lid setup left lingering baseline journal: %#v", state)
	}
}

func TestLidRecoveryPreservesExternalReturnToOriginalValue(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	adapter := newFakeAdapter(now)
	stateStore, err := store.Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	coordinator := New(stateStore, adapter, func() time.Time { return now })
	if err := coordinator.SetLidSupport(context.Background(), true); err != nil {
		t.Fatal(err)
	}
	if err := coordinator.AddLease(context.Background(), domain.Lease{ID: "manual-1", Source: domain.SourceManual}); err != nil {
		t.Fatal(err)
	}
	if _, err := coordinator.Tick(context.Background()); err != nil {
		t.Fatal(err)
	}
	adapter.sleepDisabled = false // Another actor changed Awake's applied value.
	if err := coordinator.Release(context.Background(), "manual-1"); err != nil {
		t.Fatal(err)
	}
	_, err = coordinator.Tick(context.Background())
	if err != nil {
		t.Fatalf("reconcile error = %v, want current original value accepted", err)
	}
	if adapter.sleepDisabled {
		t.Fatal("recovery overwrote another actor's change")
	}
}

type fakeAdapter struct {
	now           time.Time
	power         domain.PowerState
	observation   domain.Observation
	running       map[string]domain.ProcessID
	nextPID       int
	sleepDisabled bool
	setSleepErr   error
}

func newFakeAdapter(now time.Time) *fakeAdapter {
	return &fakeAdapter{now: now, power: domain.PowerState{OnAC: true, BatteryPercent: 100}, running: make(map[string]domain.ProcessID), nextPID: 1000}
}

func (f *fakeAdapter) ReadPower(context.Context) (domain.PowerState, error) {
	return f.power, nil
}

func (f *fakeAdapter) Observe(context.Context) (domain.Observation, error) {
	return f.observation, nil
}

func (f *fakeAdapter) ProcessIdentity(_ context.Context, pid int) (domain.ProcessID, string, error) {
	for _, process := range f.running {
		if process.PID == pid {
			return process, "caffeinate", nil
		}
	}
	return domain.ProcessID{PID: pid, StartTime: "menu-app", BootID: "boot"}, "Awake", nil
}

func (f *fakeAdapter) ProcessAlive(id domain.ProcessID) bool {
	if id.PID == 0 {
		return false
	}
	for _, running := range f.running {
		if running == id {
			return true
		}
	}
	return id.PID == 42
}

func (f *fakeAdapter) StartAssertion(_ context.Context, requestID string, _ *domain.ProcessID) (domain.ProcessID, error) {
	f.nextPID++
	id := domain.ProcessID{PID: f.nextPID, StartTime: f.now.String(), BootID: "boot"}
	f.running[requestID] = id
	return id, nil
}

func (f *fakeAdapter) StopAssertion(id domain.ProcessID) error {
	for key, running := range f.running {
		if running == id {
			delete(f.running, key)
			return nil
		}
	}
	return nil
}

func (f *fakeAdapter) ReadSleepDisabled(context.Context) (bool, error) {
	return f.sleepDisabled, nil
}

func (f *fakeAdapter) SetSleepDisabled(_ context.Context, disabled bool) error {
	if f.setSleepErr != nil {
		return f.setSleepErr
	}
	f.sleepDisabled = disabled
	return nil
}
