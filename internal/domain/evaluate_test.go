package domain

import (
	"testing"
	"time"
)

func TestSnoozeSuppressesAutomationButPreservesCommandRequest(t *testing.T) {
	location := time.FixedZone("UTC+7", 7*60*60)
	now := time.Date(2026, time.November, 20, 23, 0, 0, 0, location) // Friday
	state := State{
		SnoozeUntil: now.Add(30 * time.Minute),
		Leases:      []Lease{{ID: "run-1", Source: SourceCommand, ExpiresAt: now.Add(time.Hour)}},
		Rules: []Rule{
			{ID: "agent", Kind: RuleWorkProcess, Enabled: true, ProcessNames: []string{"agentd"}},
			{ID: "overnight", Kind: RuleSchedule, Enabled: true, Weekdays: []time.Weekday{time.Friday}, StartMinute: 22 * 60, EndMinute: 2 * 60},
		},
	}
	input := EvaluationInput{Now: now, Power: PowerState{OnAC: true, BatteryPercent: 100}, Processes: []Process{{Name: "agentd"}}}

	result := Evaluate(state, input)

	if !result.Effective {
		t.Fatal("awake should remain effective for the explicit command request")
	}
	if len(result.Requests) != 1 || result.Requests[0].ID != "run-1" {
		t.Fatalf("requests during snooze = %#v, want only command lease run-1", result.Requests)
	}
}

func TestBatteryGuardSuppressesAssertionWithoutDiscardingLease(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	state := State{BatteryGuardEnabled: true, Leases: []Lease{{ID: "run-1", Source: SourceCommand}}}
	input := EvaluationInput{Now: now, Power: PowerState{OnAC: false, BatteryPercent: 20}}

	result := Evaluate(state, input)

	if result.Effective || !result.BatterySuppressed {
		t.Fatalf("battery guard result = %#v, want suppressed and ineffective", result)
	}
	if len(result.Requests) != 1 || result.Requests[0].ID != "run-1" {
		t.Fatalf("guard discarded lease: requests = %#v", result.Requests)
	}
}

func TestBatteryGuardFailsSafeWhenChargeCannotBeRead(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	state := State{BatteryGuardEnabled: true, Leases: []Lease{{ID: "manual", Source: SourceManual}}}
	input := EvaluationInput{Now: now, Power: PowerState{OnAC: false, BatteryKnown: false}}

	result := Evaluate(state, input)

	if !result.BatterySuppressed || result.Effective || len(result.Requests) != 1 {
		t.Fatalf("unknown battery result = %#v, want safely suppressed with request preserved", result)
	}
}

func TestOvernightScheduleUsesSelectedStartDay(t *testing.T) {
	location := time.FixedZone("UTC+7", 7*60*60)
	rule := Rule{ID: "weekday", Kind: RuleSchedule, Enabled: true, Weekdays: []time.Weekday{time.Friday}, StartMinute: 22 * 60, EndMinute: 2 * 60}

	fridayLate := time.Date(2026, time.November, 20, 23, 0, 0, 0, location)
	saturdayEarly := time.Date(2026, time.November, 21, 1, 30, 0, 0, location)
	saturdayLate := time.Date(2026, time.November, 21, 2, 0, 0, 0, location)

	if !ScheduleActive(rule, fridayLate) {
		t.Fatal("Friday start day should be active after 22:00")
	}
	if !ScheduleActive(rule, saturdayEarly) {
		t.Fatal("Friday schedule should continue into Saturday before 02:00")
	}
	if ScheduleActive(rule, saturdayLate) {
		t.Fatal("schedule should be inactive at its exclusive 02:00 end")
	}
}

func TestScheduleMovesNonexistentDSTStartToNextValidLocalTime(t *testing.T) {
	location, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Fatal(err)
	}
	rule := Rule{ID: "spring", Kind: RuleSchedule, Enabled: true, Weekdays: []time.Weekday{time.Sunday}, StartMinute: 2*60 + 30, EndMinute: 3*60 + 30}
	at := time.Date(2026, time.March, 8, 3, 0, 0, 0, location)
	if !ScheduleActive(rule, at) {
		t.Fatal("nonexistent 02:30 start should move to the next valid local time, 03:00")
	}
	if ScheduleActive(rule, time.Date(2026, time.March, 8, 3, 30, 0, 0, location)) {
		t.Fatal("schedule should end at 03:30 local time")
	}
}

func TestRepeatedDSTBoundariesFormOneContinuousInterval(t *testing.T) {
	location, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Fatal(err)
	}
	rule := Rule{ID: "fall", Kind: RuleSchedule, Enabled: true, Weekdays: []time.Weekday{time.Sunday}, StartMinute: 90, EndMinute: 105}
	firstOccurrence := time.Date(2026, time.November, 1, 5, 50, 0, 0, time.UTC).In(location)  // 01:50 EDT
	secondOccurrence := time.Date(2026, time.November, 1, 6, 40, 0, 0, time.UTC).In(location) // 01:40 EST
	secondEnd := time.Date(2026, time.November, 1, 6, 45, 0, 0, time.UTC).In(location)        // 01:45 EST
	if !ScheduleActive(rule, firstOccurrence) || !ScheduleActive(rule, secondOccurrence) {
		t.Fatal("the repeated 01:30–01:45 interval should remain one active lease across both occurrences")
	}
	if ScheduleActive(rule, secondEnd) {
		t.Fatal("the repeated interval should end after the second 01:45 boundary")
	}
}

func TestActivityWatchModesMatchTheirIntendedIdentity(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	state := State{Rules: []Rule{
		{ID: "app", Kind: RuleAppOpen, Enabled: true, BundleID: "com.example.editor"},
		{ID: "work", Kind: RuleWorkProcess, Enabled: true, ProcessNames: []string{"agentd"}},
	}}
	input := EvaluationInput{
		Now:           now,
		Power:         PowerState{OnAC: true, BatteryPercent: 100},
		OpenBundleIDs: []string{"com.example.editor"},
		Processes:     []Process{{Name: "agentd"}, {Name: "node"}},
	}

	result := Evaluate(state, input)

	if len(result.Requests) != 2 {
		t.Fatalf("matched requests = %#v, want app and exact work process", result.Requests)
	}
}

func TestActivityRequestStopsImmediatelyWhenProcessDisappears(t *testing.T) {
	now := time.Date(2026, time.November, 21, 10, 0, 0, 0, time.UTC)
	state := State{
		Rules:            []Rule{{ID: "agent", Kind: RuleWorkProcess, Enabled: true, ProcessNames: []string{"agentd"}}},
		ActivityLastSeen: map[string]time.Time{"agent": now.Add(-5 * time.Second)},
	}
	input := EvaluationInput{Now: now, Power: PowerState{OnAC: true, BatteryPercent: 100, BatteryKnown: true}}
	if got := Evaluate(state, input); got.Effective || len(got.Requests) != 0 {
		t.Fatalf("request without running process = %#v, want immediately inactive", got)
	}
}
