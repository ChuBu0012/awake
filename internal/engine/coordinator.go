package engine

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"awake/internal/domain"
	"awake/internal/store"
)

var (
	ErrRestoreConflict = errors.New("sleep setting changed outside Awake; preserved the external value")
	ErrLidBaseline     = errors.New("cannot enable lid support without reading the original sleep setting")
)

type Adapter interface {
	ReadPower(context.Context) (domain.PowerState, error)
	Observe(context.Context) (domain.Observation, error)
	ProcessIdentity(context.Context, int) (domain.ProcessID, string, error)
	ProcessAlive(domain.ProcessID) bool
	StartAssertion(context.Context, string, *domain.ProcessID) (domain.ProcessID, error)
	StopAssertion(domain.ProcessID) error
	ReadSleepDisabled(context.Context) (bool, error)
	SetSleepDisabled(context.Context, bool) error
}

type Coordinator struct {
	state   *store.Store
	adapter Adapter
	now     func() time.Time
}

func New(state *store.Store, adapter Adapter, now func() time.Time) *Coordinator {
	if now == nil {
		now = time.Now
	}
	return &Coordinator{state: state, adapter: adapter, now: now}
}

func (c *Coordinator) Read() (domain.State, error) {
	return c.state.Read()
}

func (c *Coordinator) ActivateManual(ctx context.Context, duration time.Duration, owner *domain.ProcessID) error {
	if duration < 0 {
		return fmt.Errorf("duration cannot be negative")
	}
	now := c.now()
	return c.state.Update(ctx, func(state *domain.State) error {
		removeSource(state, domain.SourceManual)
		lease := domain.Lease{ID: "manual", Source: domain.SourceManual, Reason: "Manual On"}
		if duration > 0 {
			lease.ExpiresAt = now.Add(duration)
		}
		if owner != nil {
			lease.Owner = *owner
		}
		state.Leases = append(state.Leases, lease)
		state.SnoozeUntil = time.Time{}
		return nil
	})
}

// Off clears Manual On and snoozes only Activity and Schedule requests.
func (c *Coordinator) Off(ctx context.Context) error {
	now := c.now()
	return c.state.Update(ctx, func(state *domain.State) error {
		removeSource(state, domain.SourceManual)
		state.SnoozeUntil = now.Add(30 * time.Minute)
		return nil
	})
}

func (c *Coordinator) AddLease(ctx context.Context, lease domain.Lease) error {
	if strings.TrimSpace(lease.ID) == "" || lease.Source == "" {
		return fmt.Errorf("lease ID and source are required")
	}
	return c.state.Update(ctx, func(state *domain.State) error {
		for _, existing := range state.Leases {
			if existing.ID == lease.ID {
				return fmt.Errorf("lease %q already exists", lease.ID)
			}
		}
		state.Leases = append(state.Leases, lease)
		return nil
	})
}

func (c *Coordinator) Release(ctx context.Context, id string) error {
	if strings.TrimSpace(id) == "" {
		return fmt.Errorf("lease ID is required")
	}
	return c.state.Update(ctx, func(state *domain.State) error {
		leases := state.Leases[:0]
		for _, lease := range state.Leases {
			if lease.ID != id {
				leases = append(leases, lease)
			}
		}
		state.Leases = leases
		return nil
	})
}

func (c *Coordinator) SetRule(ctx context.Context, rule domain.Rule) error {
	if strings.TrimSpace(rule.ID) == "" {
		return fmt.Errorf("rule ID is required")
	}
	return c.state.Update(ctx, func(state *domain.State) error {
		for i := range state.Rules {
			if state.Rules[i].ID == rule.ID {
				state.Rules[i] = rule
				if !rule.Enabled {
					delete(state.ActivityLastSeen, rule.ID)
				}
				return nil
			}
		}
		state.Rules = append(state.Rules, rule)
		return nil
	})
}

func (c *Coordinator) RemoveRule(ctx context.Context, id string) error {
	if strings.TrimSpace(id) == "" {
		return fmt.Errorf("rule ID is required")
	}
	return c.state.Update(ctx, func(state *domain.State) error {
		rules := state.Rules[:0]
		for _, rule := range state.Rules {
			if rule.ID != id {
				rules = append(rules, rule)
			}
		}
		state.Rules = rules
		delete(state.ActivityLastSeen, id)
		return nil
	})
}

func (c *Coordinator) SetAutomationOwner(ctx context.Context, owner domain.ProcessID) error {
	if owner.PID <= 0 {
		return fmt.Errorf("automation owner PID must be a positive integer")
	}
	return c.state.Update(ctx, func(state *domain.State) error {
		state.AutomationOwner = &owner
		return nil
	})
}

func (c *Coordinator) StopAutomation(ctx context.Context) error {
	return c.state.Update(ctx, func(state *domain.State) error {
		state.AutomationOwner = nil
		return nil
	})
}

// EndSession detaches the menu bar app without snoozing schedules or Activity
// rules. Explicit command leases remain owned by their command processes.
func (c *Coordinator) EndSession(ctx context.Context) error {
	return c.state.Update(ctx, func(state *domain.State) error {
		removeSource(state, domain.SourceManual)
		state.AutomationOwner = nil
		return nil
	})
}

func (c *Coordinator) SetBatteryGuard(ctx context.Context, enabled bool) error {
	return c.state.Update(ctx, func(state *domain.State) error {
		state.BatteryGuardEnabled = enabled
		return nil
	})
}

func (c *Coordinator) SetLidSupport(ctx context.Context, enabled bool) error {
	return c.state.Update(ctx, func(state *domain.State) error {
		state.LidSupportEnabled = enabled
		return nil
	})
}

func (c *Coordinator) Tick(ctx context.Context, observed ...domain.Observation) (domain.Evaluation, error) {
	power, err := c.adapter.ReadPower(ctx)
	if err != nil {
		return domain.Evaluation{}, fmt.Errorf("read power state: %w", err)
	}
	observation, err := c.adapter.Observe(ctx)
	if err != nil {
		return domain.Evaluation{}, fmt.Errorf("read activity state: %w", err)
	}
	if len(observed) > 0 {
		observation.OpenBundleIDs = append([]string(nil), observed[0].OpenBundleIDs...)
		if observed[0].Processes != nil {
			observation.Processes = append([]domain.Process(nil), observed[0].Processes...)
		}
	}
	var result domain.Evaluation
	var started []domain.ProcessID
	var assertionsSaved bool
	err = c.state.Transact(ctx, func(state *domain.State, save func() error) error {
		now := c.now()
		pruneLeases(state, now, c.adapter.ProcessAlive)
		if state.AutomationOwner != nil && !c.adapter.ProcessAlive(*state.AutomationOwner) {
			state.AutomationOwner = nil
		}
		if state.Assertions == nil {
			state.Assertions = make(map[string]domain.ProcessID)
		}
		if state.ActivityLastSeen == nil {
			state.ActivityLastSeen = make(map[string]time.Time)
		}
		if state.LegacyAssertionPID != nil {
			identity, name, identityErr := c.adapter.ProcessIdentity(ctx, *state.LegacyAssertionPID)
			if identityErr == nil && name == "caffeinate" {
				if _, exists := state.Assertions["manual"]; !exists {
					state.Assertions["manual"] = identity
				}
			} else {
				state.RecoveryWarning = "A legacy assertion PID could not be confirmed as Awake's caffeinate process; Awake did not signal it."
			}
			state.LegacyAssertionPID = nil
		}
		if len(observed) > 0 {
			state.LastObservedBundleIDs = append([]string(nil), observed[0].OpenBundleIDs...)
			observation.OpenBundleIDs = append([]string(nil), observed[0].OpenBundleIDs...)
			if observed[0].Processes != nil {
				observation.Processes = append([]domain.Process(nil), observed[0].Processes...)
			}
		} else {
			observation.OpenBundleIDs = append([]string(nil), state.LastObservedBundleIDs...)
		}

		evaluationState := *state
		if state.AutomationOwner == nil {
			evaluationState.Rules = nil
		}
		input := domain.EvaluationInput{
			Now: now, Power: power,
			OpenBundleIDs: observation.OpenBundleIDs,
			Processes:     observation.Processes,
		}
		if state.AutomationOwner != nil {
			domain.RecordActivityMatches(state, input)
			evaluationState.ActivityLastSeen = state.ActivityLastSeen
		}
		result = domain.Evaluate(evaluationState, input)
		desired := make(map[string]domain.Lease, len(result.Requests))
		if result.Effective {
			for _, request := range result.Requests {
				desired[request.ID] = request
			}
		}

		for id, assertion := range state.Assertions {
			_, stillDesired := desired[id]
			if stillDesired && c.adapter.ProcessAlive(assertion) {
				continue
			}
			if c.adapter.ProcessAlive(assertion) {
				if err := c.adapter.StopAssertion(assertion); err != nil {
					return fmt.Errorf("stop assertion for %s: %w", id, err)
				}
			}
			delete(state.Assertions, id)
		}
		for id, request := range desired {
			if assertion, ok := state.Assertions[id]; ok && c.adapter.ProcessAlive(assertion) {
				continue
			}
			owner := requestOwner(state, request.ID)
			assertion, err := c.adapter.StartAssertion(ctx, id, owner)
			if err != nil {
				_ = save()
				return fmt.Errorf("start assertion for %s: %w", id, err)
			}
			state.Assertions[id] = assertion
			started = append(started, assertion)
		}
		if err := save(); err != nil {
			return err
		}
		assertionsSaved = true
		if err := c.reconcileLid(ctx, state, result.Effective, save); err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		if !assertionsSaved {
			for _, assertion := range started {
				_ = c.adapter.StopAssertion(assertion)
			}
		}
		return domain.Evaluation{}, err
	}
	return result, nil
}

func (c *Coordinator) reconcileLid(ctx context.Context, state *domain.State, effective bool, save func() error) error {
	wantDisabled := state.LidSupportEnabled && effective
	if wantDisabled && state.RecoveryWarning != "" && state.SleepDisabledBaseline == nil {
		return ErrLidBaseline
	}
	if wantDisabled {
		if state.SleepDisabledBaseline == nil {
			baseline, err := c.adapter.ReadSleepDisabled(ctx)
			if err != nil {
				return fmt.Errorf("%w: %v", ErrLidBaseline, err)
			}
			state.SleepDisabledBaseline = &baseline
			state.SleepDisabledApplied = nil
			if err := save(); err != nil {
				return fmt.Errorf("save sleep-setting recovery journal: %w", err)
			}
		}
		if state.SleepDisabledApplied == nil && !*state.SleepDisabledBaseline {
			current, err := c.adapter.ReadSleepDisabled(ctx)
			if err != nil {
				return fmt.Errorf("read sleep setting before apply: %w", err)
			}
			if !current {
				if err := c.adapter.SetSleepDisabled(ctx, true); err != nil {
					return fmt.Errorf("enable lid-closed support: %w", err)
				}
			}
			applied := true
			state.SleepDisabledApplied = &applied
			if err := save(); err != nil {
				return fmt.Errorf("save applied sleep-setting value: %w", err)
			}
		}
		if state.SleepDisabledApplied != nil {
			current, err := c.adapter.ReadSleepDisabled(ctx)
			if err != nil {
				return fmt.Errorf("read active sleep setting: %w", err)
			}
			if current != *state.SleepDisabledApplied {
				return ErrRestoreConflict
			}
		}
		return nil
	}

	if state.SleepDisabledBaseline == nil {
		return nil
	}
	if state.SleepDisabledApplied != nil {
		current, err := c.adapter.ReadSleepDisabled(ctx)
		if err != nil {
			return fmt.Errorf("read sleep setting before restore: %w", err)
		}
		if current != *state.SleepDisabledApplied {
			if current != *state.SleepDisabledBaseline {
				return ErrRestoreConflict
			}
		} else if err := c.adapter.SetSleepDisabled(ctx, *state.SleepDisabledBaseline); err != nil {
			return fmt.Errorf("restore original sleep setting: %w", err)
		}
	}
	state.SleepDisabledBaseline = nil
	state.SleepDisabledApplied = nil
	if err := save(); err != nil {
		return fmt.Errorf("clear sleep-setting recovery journal: %w", err)
	}
	return nil
}

func pruneLeases(state *domain.State, now time.Time, processAlive func(domain.ProcessID) bool) {
	leases := state.Leases[:0]
	for _, lease := range state.Leases {
		if lease.ID == "" || lease.Source == "" || (!lease.ExpiresAt.IsZero() && !now.Before(lease.ExpiresAt)) {
			continue
		}
		if lease.Owner.PID > 0 && !processAlive(lease.Owner) {
			continue
		}
		leases = append(leases, lease)
	}
	state.Leases = leases
}

func requestOwner(state *domain.State, requestID string) *domain.ProcessID {
	if strings.HasPrefix(requestID, "rule:") {
		if state.AutomationOwner != nil {
			owner := *state.AutomationOwner
			return &owner
		}
		return nil
	}
	for _, lease := range state.Leases {
		if lease.ID == requestID && lease.Owner.PID > 0 {
			owner := lease.Owner
			return &owner
		}
	}
	return nil
}

func removeSource(state *domain.State, source domain.Source) {
	leases := state.Leases[:0]
	for _, lease := range state.Leases {
		if lease.Source != source {
			leases = append(leases, lease)
		}
	}
	state.Leases = leases
}
