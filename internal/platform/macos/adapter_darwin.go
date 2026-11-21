//go:build darwin

package macos

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	"awake/internal/domain"
)

type Runner interface {
	Run(context.Context, string, ...string) ([]byte, error)
}

type Adapter struct {
	runner Runner
	signal func(int, syscall.Signal) error
}

func New() *Adapter { return NewWithRunner(execRunner{}) }

func NewWithRunner(runner Runner) *Adapter {
	return NewWithRunnerAndSignaler(runner, syscall.Kill)
}

func NewWithRunnerAndSignaler(runner Runner, signal func(int, syscall.Signal) error) *Adapter {
	return &Adapter{runner: runner, signal: signal}
}

func (a *Adapter) ReadPower(ctx context.Context) (domain.PowerState, error) {
	output, err := a.runner.Run(ctx, "/usr/bin/pmset", "-g", "batt")
	if err != nil {
		return domain.PowerState{}, err
	}
	text := string(output)
	state := domain.PowerState{OnAC: strings.Contains(text, "AC Power")}
	match := batteryPercentage.FindStringSubmatch(text)
	if len(match) == 2 {
		percent, err := strconv.Atoi(match[1])
		if err != nil || percent < 0 || percent > 100 {
			return domain.PowerState{}, fmt.Errorf("invalid battery percentage reported by pmset")
		}
		state.BatteryPercent = percent
		state.BatteryKnown = true
	}
	return state, nil
}

func (a *Adapter) Observe(ctx context.Context) (domain.Observation, error) {
	output, err := a.runner.Run(ctx, "/bin/ps", "-axo", "comm=")
	if err != nil {
		return domain.Observation{}, err
	}
	observation := domain.Observation{}
	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	for scanner.Scan() {
		name := filepath.Base(strings.TrimSpace(scanner.Text()))
		if name != "" {
			observation.Processes = append(observation.Processes, domain.Process{Name: name})
		}
	}
	if err := scanner.Err(); err != nil {
		return domain.Observation{}, err
	}
	return observation, nil
}

func (a *Adapter) ProcessIdentity(ctx context.Context, pid int) (domain.ProcessID, string, error) {
	if pid <= 1 {
		return domain.ProcessID{}, "", fmt.Errorf("invalid process ID")
	}
	pidText := strconv.Itoa(pid)
	nameOutput, err := a.runner.Run(ctx, "/bin/ps", "-p", pidText, "-o", "comm=")
	if err != nil {
		return domain.ProcessID{}, "", err
	}
	startOutput, err := a.runner.Run(ctx, "/bin/ps", "-p", pidText, "-o", "lstart=")
	if err != nil {
		return domain.ProcessID{}, "", err
	}
	start := strings.TrimSpace(string(startOutput))
	name := filepath.Base(strings.TrimSpace(string(nameOutput)))
	if start == "" || name == "" {
		return domain.ProcessID{}, "", os.ErrProcessDone
	}
	bootOutput, err := a.runner.Run(ctx, "/usr/sbin/sysctl", "-n", "kern.boottime")
	if err != nil {
		return domain.ProcessID{}, "", err
	}
	return domain.ProcessID{PID: pid, StartTime: start, BootID: strings.TrimSpace(string(bootOutput))}, name, nil
}

func (a *Adapter) ProcessAlive(id domain.ProcessID) bool {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	current, _, err := a.ProcessIdentity(ctx, id.PID)
	return err == nil && current.StartTime == id.StartTime && current.BootID == id.BootID
}

func (a *Adapter) StartAssertion(ctx context.Context, requestID string, owner *domain.ProcessID) (domain.ProcessID, error) {
	if strings.TrimSpace(requestID) == "" {
		return domain.ProcessID{}, fmt.Errorf("assertion request ID is required")
	}
	args := []string{"-i"}
	if owner != nil {
		if owner.PID <= 1 || owner.StartTime == "" || owner.BootID == "" {
			return domain.ProcessID{}, fmt.Errorf("assertion owner identity is incomplete")
		}
		current, _, err := a.ProcessIdentity(ctx, owner.PID)
		if err != nil || current.StartTime != owner.StartTime || current.BootID != owner.BootID {
			return domain.ProcessID{}, fmt.Errorf("assertion owner process identity is stale")
		}
		args = append(args, "-w", strconv.Itoa(owner.PID))
	}
	command := exec.Command("/usr/bin/caffeinate", args...)
	command.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	command.Stdin = nil
	command.Stdout = nil
	command.Stderr = nil
	if err := command.Start(); err != nil {
		return domain.ProcessID{}, fmt.Errorf("start caffeinate assertion: %w", err)
	}
	processID := command.Process.Pid
	for attempt := 0; attempt < 20; attempt++ {
		identity, name, err := a.ProcessIdentity(ctx, processID)
		if err == nil && name == "caffeinate" {
			if err := command.Process.Release(); err != nil {
				return domain.ProcessID{}, fmt.Errorf("release caffeinate process handle: %w", err)
			}
			return identity, nil
		}
		time.Sleep(25 * time.Millisecond)
	}
	_ = command.Process.Kill()
	_ = command.Process.Release()
	return domain.ProcessID{}, fmt.Errorf("caffeinate process did not become observable")
}

func (a *Adapter) StopAssertion(id domain.ProcessID) error {
	if id.PID <= 1 || id.StartTime == "" || id.BootID == "" {
		return fmt.Errorf("refusing to signal an incomplete process identity")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	current, name, err := a.ProcessIdentity(ctx, id.PID)
	if err != nil {
		if errors.Is(err, os.ErrProcessDone) {
			return nil
		}
		return err
	}
	if name != "caffeinate" || current.StartTime != id.StartTime || current.BootID != id.BootID {
		return fmt.Errorf("refusing to signal PID %d: process identity does not match caffeinate", id.PID)
	}
	if err := a.signal(id.PID, syscall.SIGTERM); err != nil && !errors.Is(err, syscall.ESRCH) {
		return fmt.Errorf("stop caffeinate assertion: %w", err)
	}
	return nil
}

func (a *Adapter) ReadSleepDisabled(ctx context.Context) (bool, error) {
	output, err := a.runner.Run(ctx, "/usr/bin/pmset", "-g")
	if err != nil {
		return false, err
	}
	match := sleepDisabled.FindStringSubmatch(string(output))
	if len(match) != 2 {
		return false, fmt.Errorf("pmset did not report SleepDisabled")
	}
	return match[1] == "1", nil
}

func (a *Adapter) SetSleepDisabled(ctx context.Context, disabled bool) error {
	value := "0"
	if disabled {
		value = "1"
	}
	_, err := a.runner.Run(ctx, "/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", value)
	return err
}

type execRunner struct{}

func (execRunner) Run(ctx context.Context, path string, args ...string) ([]byte, error) {
	command := exec.CommandContext(ctx, path, args...)
	output, err := command.CombinedOutput()
	if err != nil {
		return output, fmt.Errorf("%s %s: %w: %s", path, strings.Join(args, " "), err, strings.TrimSpace(string(output)))
	}
	return output, nil
}

var (
	batteryPercentage = regexp.MustCompile(`([0-9]{1,3})%`)
	sleepDisabled     = regexp.MustCompile(`(?m)^\s*SleepDisabled\s+([01])\s*$`)
)
