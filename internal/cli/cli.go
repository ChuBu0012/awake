package cli

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"awake/internal/domain"
	"awake/internal/engine"
)

type IdentityProvider interface {
	ProcessIdentity(context.Context, int) (domain.ProcessID, string, error)
}

type CommandRunner interface {
	Run(context.Context, []string) (int, error)
}

type CLI struct {
	coordinator *engine.Coordinator
	identity    IdentityProvider
	commands    CommandRunner
	stdout      io.Writer
	stderr      io.Writer
	now         func() time.Time
}

func New(coordinator *engine.Coordinator, identity IdentityProvider, commands CommandRunner, stdout, stderr io.Writer) *CLI {
	if stdout == nil {
		stdout = io.Discard
	}
	if stderr == nil {
		stderr = io.Discard
	}
	return &CLI{coordinator: coordinator, identity: identity, commands: commands, stdout: stdout, stderr: stderr, now: time.Now}
}

type ExitError struct{ Code int }

func (e ExitError) Error() string { return fmt.Sprintf("command exited with status %d", e.Code) }

type Status struct {
	Active            bool           `json:"active"`
	BatterySuppressed bool           `json:"battery_suppressed"`
	BatteryGuard      bool           `json:"battery_guard_enabled"`
	LidSupport        bool           `json:"lid_support_enabled"`
	SnoozedUntil      time.Time      `json:"snoozed_until,omitempty"`
	Requests          []domain.Lease `json:"requests"`
	Rules             []domain.Rule  `json:"rules"`
	RecoveryPending   bool           `json:"recovery_pending"`
	RecoveryWarning   string         `json:"recovery_warning,omitempty"`
}

func (c *CLI) Run(ctx context.Context, args []string) error {
	if len(args) == 0 {
		args = []string{"status"}
	}
	command := args[0]
	args = args[1:]
	switch command {
	case "on", "start":
		return c.on(ctx, args)
	case "off", "stop":
		return c.off(ctx, args)
	case "status":
		return c.status(ctx, args)
	case "run", "exec":
		return c.run(ctx, args)
	case "tick":
		return c.tick(ctx, args)
	case "recover":
		if len(args) != 0 {
			return fmt.Errorf("usage: awake recover")
		}
		_, err := c.coordinator.Tick(ctx)
		return err
	case "stop-automation":
		if len(args) != 0 {
			return fmt.Errorf("usage: awake stop-automation")
		}
		if err := c.coordinator.StopAutomation(ctx); err != nil {
			return err
		}
		_, err := c.coordinator.Tick(ctx)
		return err
	case "session-end":
		if len(args) != 0 {
			return fmt.Errorf("usage: awake session-end")
		}
		if err := c.coordinator.EndSession(ctx); err != nil {
			return err
		}
		_, err := c.coordinator.Tick(ctx)
		return err
	case "rule":
		return c.rule(ctx, args)
	case "set":
		return c.set(ctx, args)
	case "setup":
		return c.setup(ctx, args)
	case "help", "--help", "-h":
		c.help()
		return nil
	default:
		return fmt.Errorf("unknown command %q; run 'awake help'", command)
	}
}

func (c *CLI) on(ctx context.Context, args []string) error {
	duration := time.Duration(0)
	var owner *domain.ProcessID
	if len(args) > 0 && !strings.HasPrefix(args[0], "--") {
		parsed, err := ParseDuration(args[0])
		if err != nil {
			return err
		}
		duration = parsed
		args = args[1:]
	}
	if len(args) > 0 {
		if len(args) != 2 || args[0] != "--owner-pid" {
			return fmt.Errorf("usage: awake on [duration] [--owner-pid PID]")
		}
		pid, err := parsePID(args[1])
		if err != nil {
			return err
		}
		identity, _, err := c.identity.ProcessIdentity(ctx, pid)
		if err != nil {
			return fmt.Errorf("resolve manual request owner: %w", err)
		}
		owner = &identity
	}
	if err := c.coordinator.ActivateManual(ctx, duration, owner); err != nil {
		return err
	}
	result, err := c.coordinator.Tick(ctx)
	if err != nil {
		return err
	}
	c.printEvaluation(result)
	return nil
}

func (c *CLI) off(ctx context.Context, args []string) error {
	if len(args) != 0 {
		return fmt.Errorf("usage: awake off")
	}
	if err := c.coordinator.Off(ctx); err != nil {
		return err
	}
	result, err := c.coordinator.Tick(ctx)
	if err != nil {
		return err
	}
	c.printEvaluation(result)
	return nil
}

func (c *CLI) status(ctx context.Context, args []string) error {
	jsonOutput := len(args) == 1 && args[0] == "--json"
	if len(args) != 0 && !jsonOutput {
		return fmt.Errorf("usage: awake status [--json]")
	}
	result, err := c.coordinator.Tick(ctx)
	if err != nil {
		return err
	}
	state, err := c.coordinator.Read()
	if err != nil {
		return err
	}
	status := statusFrom(state, result)
	if jsonOutput {
		encoder := json.NewEncoder(c.stdout)
		encoder.SetEscapeHTML(true)
		return encoder.Encode(status)
	}
	c.printStatus(status)
	return nil
}

func (c *CLI) run(ctx context.Context, args []string) error {
	if len(args) == 0 || strings.TrimSpace(args[0]) == "" {
		return fmt.Errorf("usage: awake run <command> [args...]")
	}
	owner, _, err := c.identity.ProcessIdentity(ctx, os.Getpid())
	if err != nil {
		return fmt.Errorf("identify awake run process: %w", err)
	}
	leaseID, err := newLeaseID()
	if err != nil {
		return err
	}
	lease := domain.Lease{ID: leaseID, Source: domain.SourceCommand, Reason: "Command: " + filepath.Base(args[0]), Owner: owner}
	if err := c.coordinator.AddLease(ctx, lease); err != nil {
		return err
	}
	if _, err := c.coordinator.Tick(ctx); err != nil {
		fmt.Fprintf(c.stderr, "Awake warning: request recorded but sleep prevention could not be fully reconciled: %v\n", err)
	}

	code, runErr := c.commands.Run(ctx, args)
	cleanupCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := c.coordinator.Release(cleanupCtx, leaseID); err != nil {
		return errors.Join(runErr, fmt.Errorf("release command request: %w", err))
	}
	if _, err := c.coordinator.Tick(cleanupCtx); err != nil {
		return errors.Join(runErr, fmt.Errorf("reconcile after command: %w", err))
	}
	if runErr != nil {
		return runErr
	}
	if code != 0 {
		return ExitError{Code: code}
	}
	return nil
}

func (c *CLI) tick(ctx context.Context, args []string) error {
	var ownerPID int
	var bundleIDs []string
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--automation-owner-pid":
			if i+1 >= len(args) {
				return fmt.Errorf("--automation-owner-pid requires a PID")
			}
			pid, err := parsePID(args[i+1])
			if err != nil {
				return err
			}
			ownerPID = pid
			i++
		case "--bundle-id":
			if i+1 >= len(args) || strings.TrimSpace(args[i+1]) == "" {
				return fmt.Errorf("--bundle-id requires a bundle identifier")
			}
			bundleIDs = append(bundleIDs, args[i+1])
			i++
		default:
			return fmt.Errorf("unknown tick option %q", args[i])
		}
	}
	if ownerPID > 0 {
		owner, _, err := c.identity.ProcessIdentity(ctx, ownerPID)
		if err != nil {
			return fmt.Errorf("resolve automation owner: %w", err)
		}
		if err := c.coordinator.SetAutomationOwner(ctx, owner); err != nil {
			return err
		}
	} else if err := c.coordinator.StopAutomation(ctx); err != nil {
		return err
	}
	_, err := c.coordinator.Tick(ctx, domain.Observation{OpenBundleIDs: bundleIDs})
	return err
}

func (c *CLI) set(ctx context.Context, args []string) error {
	if len(args) != 2 || (args[1] != "on" && args[1] != "off") {
		return fmt.Errorf("usage: awake set battery-guard|lid-support on|off")
	}
	enabled := args[1] == "on"
	switch args[0] {
	case "battery-guard":
		if err := c.coordinator.SetBatteryGuard(ctx, enabled); err != nil {
			return err
		}
	case "lid-support":
		if err := c.coordinator.SetLidSupport(ctx, enabled); err != nil {
			return err
		}
	default:
		return fmt.Errorf("unknown setting %q", args[0])
	}
	result, err := c.coordinator.Tick(ctx)
	if err == nil {
		c.printEvaluation(result)
	}
	return err
}

func (c *CLI) setup(ctx context.Context, args []string) error {
	if len(args) != 0 {
		return fmt.Errorf("usage: awake setup")
	}
	path, err := findSetupScript()
	if err != nil {
		return err
	}
	code, err := c.commands.Run(ctx, []string{path})
	if err != nil {
		return err
	}
	if code != 0 {
		return ExitError{Code: code}
	}
	return nil
}

func findSetupScript() (string, error) {
	if configured := os.Getenv("AWAKE_SETUP_SCRIPT"); configured != "" {
		if executableFile(configured) {
			return configured, nil
		}
		return "", fmt.Errorf("configured sudoers setup helper is not executable")
	}
	home, _ := os.UserHomeDir()
	executable, _ := os.Executable()
	workingDirectory, _ := os.Getwd()
	candidates := []string{
		filepath.Join(home, ".local", "lib", "awake", "setup-sudoers.sh"),
		filepath.Join(filepath.Dir(executable), "..", "lib", "awake", "setup-sudoers.sh"),
		filepath.Join(filepath.Dir(executable), "setup-sudoers.sh"),
		filepath.Join(workingDirectory, "scripts", "setup-sudoers.sh"),
	}
	for _, candidate := range candidates {
		if executableFile(candidate) {
			return candidate, nil
		}
	}
	return "", fmt.Errorf("sudoers setup helper not found; reinstall Awake or run make setup from the source checkout")
}

func executableFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular() && info.Mode().Perm()&0o111 != 0
}

func (c *CLI) rule(ctx context.Context, args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: awake rule app|process|schedule|enable|disable|remove ...")
	}
	switch args[0] {
	case "app":
		if len(args) != 4 {
			return fmt.Errorf("usage: awake rule app ID NAME BUNDLE_ID")
		}
		return c.coordinator.SetRule(ctx, domain.Rule{ID: args[1], Name: args[2], Kind: domain.RuleAppOpen, BundleID: args[3], Enabled: true})
	case "process":
		if len(args) != 4 || !validProcessName(args[3]) {
			return fmt.Errorf("usage: awake rule process ID NAME EXACT_PROCESS_NAME")
		}
		return c.coordinator.SetRule(ctx, domain.Rule{ID: args[1], Name: args[2], Kind: domain.RuleWorkProcess, ProcessNames: []string{args[3]}, Enabled: true})
	case "schedule":
		if len(args) != 6 {
			return fmt.Errorf("usage: awake rule schedule ID NAME DAYS START END")
		}
		days, err := parseWeekdays(args[3])
		if err != nil {
			return err
		}
		start, err := parseClockTime(args[4])
		if err != nil {
			return err
		}
		end, err := parseClockTime(args[5])
		if err != nil {
			return err
		}
		return c.coordinator.SetRule(ctx, domain.Rule{ID: args[1], Name: args[2], Kind: domain.RuleSchedule, Weekdays: days, StartMinute: start, EndMinute: end, Enabled: true})
	case "enable", "disable", "remove":
		if len(args) != 2 {
			return fmt.Errorf("usage: awake rule %s ID", args[0])
		}
		state, err := c.coordinator.Read()
		if err != nil {
			return err
		}
		if args[0] == "remove" {
			return c.coordinator.RemoveRule(ctx, args[1])
		}
		for _, rule := range state.Rules {
			if rule.ID == args[1] {
				rule.Enabled = args[0] == "enable"
				return c.coordinator.SetRule(ctx, rule)
			}
		}
		return fmt.Errorf("rule %q was not found", args[1])
	default:
		return fmt.Errorf("unknown rule operation %q", args[0])
	}
}

func statusFrom(state domain.State, evaluation domain.Evaluation) Status {
	return Status{
		Active:            evaluation.Effective,
		BatterySuppressed: evaluation.BatterySuppressed,
		BatteryGuard:      state.BatteryGuardEnabled,
		LidSupport:        state.LidSupportEnabled,
		SnoozedUntil:      state.SnoozeUntil,
		Requests:          append([]domain.Lease{}, evaluation.Requests...),
		Rules:             append([]domain.Rule{}, state.Rules...),
		RecoveryPending:   state.SleepDisabledBaseline != nil || state.RecoveryWarning != "" || state.LegacyAssertionPID != nil,
		RecoveryWarning:   state.RecoveryWarning,
	}
}

func (c *CLI) printEvaluation(evaluation domain.Evaluation) {
	if evaluation.BatterySuppressed {
		fmt.Fprintln(c.stdout, "Awake request saved; Battery Guard is suppressing sleep prevention until charging resumes or battery rises above 20%.")
		return
	}
	if evaluation.Effective {
		fmt.Fprintln(c.stdout, "Awake is active.")
	} else {
		fmt.Fprintln(c.stdout, "Awake is inactive.")
	}
}

func (c *CLI) printStatus(status Status) {
	if status.BatterySuppressed {
		fmt.Fprintln(c.stdout, "Status: Suppressed by Battery Guard")
	} else if status.Active {
		fmt.Fprintln(c.stdout, "Status: Active")
	} else {
		fmt.Fprintln(c.stdout, "Status: Inactive")
	}
	for _, request := range status.Requests {
		reason := request.Reason
		if reason == "" {
			reason = string(request.Source)
		}
		fmt.Fprintf(c.stdout, "  • %s\n", reason)
	}
	if status.RecoveryPending {
		fmt.Fprintln(c.stdout, "Recovery: a system sleep setting needs reconciliation")
		if status.RecoveryWarning != "" {
			fmt.Fprintf(c.stdout, "  %s\n", status.RecoveryWarning)
		}
	}
}

func (c *CLI) help() {
	fmt.Fprintln(c.stdout, "Awake — local sleep prevention")
	fmt.Fprintln(c.stdout, "  awake on [duration] [--owner-pid PID]")
	fmt.Fprintln(c.stdout, "  awake off")
	fmt.Fprintln(c.stdout, "  awake status [--json]")
	fmt.Fprintln(c.stdout, "  awake run <command> [args...]")
	fmt.Fprintln(c.stdout, "  awake tick [--automation-owner-pid PID] [--bundle-id ID ...]")
	fmt.Fprintln(c.stdout, "  awake rule app|process|schedule ...")
	fmt.Fprintln(c.stdout, "  awake set battery-guard|lid-support on|off")
	fmt.Fprintln(c.stdout, "  awake setup")
	fmt.Fprintln(c.stdout, "  awake recover")
}

func parsePID(value string) (int, error) {
	pid, err := strconv.Atoi(value)
	if err != nil || pid <= 1 {
		return 0, fmt.Errorf("PID must be a positive process identifier")
	}
	return pid, nil
}

func validProcessName(value string) bool {
	if value == "" || value != strings.TrimSpace(value) || filepath.Base(value) != value || value == "." || value == ".." || strings.ContainsAny(value, "/\\\x00\n\r\t") {
		return false
	}
	for _, char := range value {
		if !(char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z' || char >= '0' && char <= '9' || strings.ContainsRune("._+- ()", char)) {
			return false
		}
	}
	return true
}

func parseWeekdays(value string) ([]time.Weekday, error) {
	weekdayMap := map[string]time.Weekday{"sun": time.Sunday, "mon": time.Monday, "tue": time.Tuesday, "wed": time.Wednesday, "thu": time.Thursday, "fri": time.Friday, "sat": time.Saturday}
	parts := strings.Split(value, ",")
	days := make([]time.Weekday, 0, len(parts))
	seen := make(map[time.Weekday]bool)
	for _, part := range parts {
		day, ok := weekdayMap[strings.ToLower(part)]
		if !ok || seen[day] {
			return nil, fmt.Errorf("invalid or duplicate weekday %q", part)
		}
		seen[day] = true
		days = append(days, day)
	}
	return days, nil
}

func parseClockTime(value string) (int, error) {
	parsed, err := time.Parse("15:04", value)
	if err != nil {
		return 0, fmt.Errorf("time must use 24-hour HH:MM format: %w", err)
	}
	return parsed.Hour()*60 + parsed.Minute(), nil
}

func newLeaseID() (string, error) {
	var bytes [16]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", fmt.Errorf("create request ID: %w", err)
	}
	return "run:" + hex.EncodeToString(bytes[:]), nil
}
