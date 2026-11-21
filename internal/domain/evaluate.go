package domain

import "time"

const CurrentSchemaVersion = 1

type Source string

const (
	SourceManual   Source = "manual"
	SourceCommand  Source = "command"
	SourceActivity Source = "activity"
	SourceSchedule Source = "schedule"
)

type RuleKind string

const (
	RuleAppOpen     RuleKind = "app_open"
	RuleWorkProcess RuleKind = "work_process"
	RuleSchedule    RuleKind = "schedule"
)

type Lease struct {
	ID        string    `json:"id"`
	Source    Source    `json:"source"`
	Reason    string    `json:"reason,omitempty"`
	ExpiresAt time.Time `json:"expires_at,omitempty"`
	Owner     ProcessID `json:"owner,omitempty"`
}

type ProcessID struct {
	PID       int    `json:"pid"`
	StartTime string `json:"start_time,omitempty"`
	BootID    string `json:"boot_id,omitempty"`
}

type Rule struct {
	ID           string         `json:"id"`
	Name         string         `json:"name,omitempty"`
	Kind         RuleKind       `json:"kind"`
	Enabled      bool           `json:"enabled"`
	BundleID     string         `json:"bundle_id,omitempty"`
	ProcessNames []string       `json:"process_names,omitempty"`
	Weekdays     []time.Weekday `json:"weekdays,omitempty"`
	StartMinute  int            `json:"start_minute,omitempty"`
	EndMinute    int            `json:"end_minute,omitempty"`
	Active       bool           `json:"active,omitempty"`
	AppOpen      bool           `json:"app_open,omitempty"`
	SmartActive  bool           `json:"smart_active,omitempty"`
}

type State struct {
	SchemaVersion               int                  `json:"schema_version"`
	BatteryGuardEnabled         bool                 `json:"battery_guard_enabled"`
	LidSupportEnabled           bool                 `json:"lid_support_enabled,omitempty"`
	SnoozeUntil                 time.Time            `json:"snooze_until,omitempty"`
	Leases                      []Lease              `json:"leases,omitempty"`
	Rules                       []Rule               `json:"rules,omitempty"`
	ActivityLastSeen            map[string]time.Time `json:"activity_last_seen,omitempty"`
	Assertions                  map[string]ProcessID `json:"assertions,omitempty"`
	AutomationOwner             *ProcessID           `json:"automation_owner,omitempty"`
	LastObservedBundleIDs       []string             `json:"last_observed_bundle_ids,omitempty"`
	LegacyAssertionPID          *int                 `json:"legacy_assertion_pid,omitempty"`
	RecoveryWarning             string               `json:"recovery_warning,omitempty"`
	MigrationRequired           bool                 `json:"-"`
	SleepDisabledBaseline       *bool                `json:"sleep_disabled_baseline,omitempty"`
	SleepDisabledApplied        *bool                `json:"sleep_disabled_applied,omitempty"`
	ClamshellBatteryActiveSince time.Time            `json:"clamshell_battery_active_since,omitempty"`
}

type PowerState struct {
	OnAC           bool `json:"on_ac"`
	BatteryPercent int  `json:"battery_percent"`
	BatteryKnown   bool `json:"battery_known"`
}

type Process struct {
	Name       string  `json:"name"`
	CPUPercent float64 `json:"cpu_percent,omitempty"`
}

type Observation struct {
	OpenBundleIDs []string  `json:"open_bundle_ids,omitempty"`
	Processes     []Process `json:"processes,omitempty"`
	LidClosed     bool      `json:"lid_closed,omitempty"`
}

type EvaluationInput struct {
	Now           time.Time
	Power         PowerState
	LidClosed     bool
	OpenBundleIDs []string
	Processes     []Process
}

type Evaluation struct {
	Effective         bool
	BatterySuppressed bool
	ClamshellTimedOut bool
	Requests          []Lease
}

// Evaluate combines live leases and enabled rules without mutating durable state.
// Snooze filters only Activity and Schedule sources. Battery Guard suppresses
// the effective assertion but preserves eligible requests for later resumption.
func Evaluate(state State, input EvaluationInput) Evaluation {
	requests := make([]Lease, 0, len(state.Leases)+len(state.Rules))
	snoozed := input.Now.Before(state.SnoozeUntil)

	for _, lease := range state.Leases {
		if lease.ID == "" || lease.Source == "" || (!lease.ExpiresAt.IsZero() && !input.Now.Before(lease.ExpiresAt)) {
			continue
		}
		if snoozed && isAutomationSource(lease.Source) {
			continue
		}
		requests = append(requests, lease)
	}

	for _, rule := range state.Rules {
		if !rule.Enabled || rule.ID == "" || (snoozed && isAutomationRule(rule.Kind)) {
			continue
		}
		matched := ruleMatches(rule, state, input)
		if matched {
			requests = append(requests, Lease{ID: "rule:" + rule.ID, Source: sourceForRule(rule.Kind), Reason: ruleDisplayName(rule)})
		}
	}

	batteryLowOrUnknown := !input.Power.BatteryKnown || input.Power.BatteryPercent <= 20
	batterySuppressed := state.BatteryGuardEnabled && !input.Power.OnAC && batteryLowOrUnknown && len(requests) > 0

	// Backpack Clamshell Safety: Cap sleep prevention on battery with lid closed to max 2 hours
	clamshellTimedOut := false
	if !input.Power.OnAC && input.Power.BatteryKnown && input.LidClosed && len(requests) > 0 {
		if !state.ClamshellBatteryActiveSince.IsZero() && input.Now.Sub(state.ClamshellBatteryActiveSince) >= 2*time.Hour {
			clamshellTimedOut = true
		}
	}

	effective := len(requests) > 0 && !batterySuppressed && !clamshellTimedOut
	return Evaluation{
		Effective:         effective,
		BatterySuppressed: batterySuppressed,
		ClamshellTimedOut: clamshellTimedOut,
		Requests:          requests,
	}
}

// RecordActivityMatches refreshes activity timestamps for matching rules.
func RecordActivityMatches(state *State, input EvaluationInput) {
	if state.ActivityLastSeen == nil {
		state.ActivityLastSeen = make(map[string]time.Time)
	}
	for _, rule := range state.Rules {
		if !rule.Enabled || !isActivityRule(rule.Kind) {
			continue
		}
		switch rule.Kind {
		case RuleAppOpen:
			if rule.BundleID != "" && containsString(input.OpenBundleIDs, rule.BundleID) {
				state.ActivityLastSeen[rule.ID] = input.Now
			}
		case RuleWorkProcess:
			for _, proc := range input.Processes {
				if containsString(rule.ProcessNames, proc.Name) {
					// If CPU is actively burning (>5%) or unmeasured (0.0 without smart mode), mark active
					if !rule.SmartActive || proc.CPUPercent >= 5.0 {
						state.ActivityLastSeen[rule.ID] = input.Now
					}
					break
				}
			}
		}
	}
}

func isActivityRule(kind RuleKind) bool {
	return kind == RuleAppOpen || kind == RuleWorkProcess
}

func isAutomationRule(kind RuleKind) bool {
	return isActivityRule(kind) || kind == RuleSchedule
}

func isAutomationSource(source Source) bool {
	return source == SourceActivity || source == SourceSchedule
}

func sourceForRule(kind RuleKind) Source {
	if kind == RuleSchedule {
		return SourceSchedule
	}
	return SourceActivity
}

func ruleDisplayName(rule Rule) string {
	if rule.Name != "" {
		return rule.Name
	}
	return rule.ID
}

func ruleMatches(rule Rule, state State, input EvaluationInput) bool {
	switch rule.Kind {
	case RuleAppOpen:
		return rule.BundleID != "" && containsString(input.OpenBundleIDs, rule.BundleID)
	case RuleWorkProcess:
		var foundProc *Process
		for i, process := range input.Processes {
			if containsString(rule.ProcessNames, process.Name) {
				foundProc = &input.Processes[i]
				break
			}
		}
		// If process is not running at all, stop immediately (0s delay per decisions.md)
		if foundProc == nil {
			return false
		}
		// If Smart Activity is enabled:
		if rule.SmartActive {
			// CPU >= 5% is active
			if foundProc.CPUPercent >= 5.0 {
				return true
			}
			// CPU < 5%: check 60s sustained idle debounce window
			if lastSeen, exists := state.ActivityLastSeen[rule.ID]; exists {
				return input.Now.Sub(lastSeen) < 60*time.Second
			}
			return false
		}
		return true
	case RuleSchedule:
		return ScheduleActive(rule, input.Now)
	default:
		return false
	}
}

func containsString(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}

// ScheduleActive evaluates local wall-clock windows. For an overnight window,
// the selected weekday is the day on which the window starts.
func ScheduleActive(rule Rule, at time.Time) bool {
	if rule.Kind != RuleSchedule || rule.StartMinute < 0 || rule.StartMinute >= 24*60 || rule.EndMinute < 0 || rule.EndMinute >= 24*60 || rule.StartMinute == rule.EndMinute {
		return false
	}
	location := at.Location()
	today := time.Date(at.Year(), at.Month(), at.Day(), 12, 0, 0, 0, location)
	if containsWeekday(rule.Weekdays, today.Weekday()) && inScheduleWindow(rule, today, at) {
		return true
	}
	if rule.StartMinute > rule.EndMinute {
		previousStartDay := today.AddDate(0, 0, -1)
		return containsWeekday(rule.Weekdays, previousStartDay.Weekday()) && inScheduleWindow(rule, previousStartDay, at)
	}
	return false
}

func inScheduleWindow(rule Rule, startDay, at time.Time) bool {
	start, startOK := resolveLocalBoundary(startDay, rule.StartMinute, true)
	endDay := startDay
	if rule.StartMinute > rule.EndMinute {
		endDay = startDay.AddDate(0, 0, 1)
	}
	end, endOK := resolveLocalBoundary(endDay, rule.EndMinute, false)
	return startOK && endOK && !at.Before(start) && at.Before(end)
}

// resolveLocalBoundary maps a wall-clock minute to a real instant.
func resolveLocalBoundary(day time.Time, minute int, startBoundary bool) (time.Time, bool) {
	location := day.Location()
	year, month, date := day.Date()
	wall := time.Date(year, month, date, minute/60, minute%60, 0, 0, time.UTC)
	offsets := make(map[int]struct{}, 2)
	for _, delta := range []int{-24, 0, 24} {
		probe := time.Date(year, month, date+delta, 12, 0, 0, 0, location)
		_, offset := probe.Zone()
		offsets[offset] = struct{}{}
	}
	matching := func(localMinute int) []time.Time {
		var instants []time.Time
		for offset := range offsets {
			candidate := wall.Add(time.Duration(localMinute-minute)*time.Minute - time.Duration(offset)*time.Second)
			local := candidate.In(location)
			ly, lm, ld := local.Date()
			if ly == year && lm == month && ld == date && local.Hour()*60+local.Minute() == localMinute {
				instants = append(instants, candidate)
			}
		}
		return instants
	}
	exact := matching(minute)
	if len(exact) > 0 {
		selected := exact[0]
		if startBoundary {
			for _, candidate := range exact[1:] {
				if candidate.Before(selected) {
					selected = candidate
				}
			}
		} else {
			for _, candidate := range exact[1:] {
				if candidate.After(selected) {
					selected = candidate
				}
			}
		}
		return selected, true
	}
	for nextMinute := minute + 1; nextMinute < 24*60; nextMinute++ {
		if candidates := matching(nextMinute); len(candidates) > 0 {
			selected := candidates[0]
			for _, candidate := range candidates[1:] {
				if candidate.Before(selected) {
					selected = candidate
				}
			}
			return selected, true
		}
	}
	return time.Time{}, false
}

func containsWeekday(values []time.Weekday, wanted time.Weekday) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}
