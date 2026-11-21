package macos

import (
	"context"
	"reflect"
	"strings"
	"syscall"
	"testing"

	"awake/internal/domain"
)

func TestReadPowerParsesACAndBatteryPercentage(t *testing.T) {
	runner := &fakeRunner{output: []byte("Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t92%; charged; 0:00 remaining\n")}
	adapter := NewWithRunner(runner)

	got, err := adapter.ReadPower(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !got.OnAC || got.BatteryPercent != 92 {
		t.Fatalf("power state = %#v, want AC at 92%%", got)
	}
	if runner.path != "/usr/bin/pmset" || !reflect.DeepEqual(runner.args, []string{"-g", "batt"}) {
		t.Fatalf("power command = %s %#v", runner.path, runner.args)
	}
}

func TestReadPowerMarksUnknownBatteryPercentage(t *testing.T) {
	runner := &fakeRunner{output: []byte("Now drawing from 'Battery Power'\n")}
	adapter := NewWithRunner(runner)

	got, err := adapter.ReadPower(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if got.OnAC || got.BatteryKnown {
		t.Fatalf("unknown battery percentage = %#v, want battery source and unknown percentage", got)
	}
}

func TestSetSleepDisabledUsesOnlyAllowedSudoCommand(t *testing.T) {
	runner := &fakeRunner{}
	adapter := NewWithRunner(runner)
	if err := adapter.SetSleepDisabled(context.Background(), true); err != nil {
		t.Fatal(err)
	}
	want := []string{"-n", "/usr/bin/pmset", "-a", "disablesleep", "1"}
	if runner.path != "/usr/bin/sudo" || !reflect.DeepEqual(runner.args, want) {
		t.Fatalf("privileged command = %s %#v, want sudo with narrow pmset args", runner.path, runner.args)
	}
}

func TestSetSleepDisabledUsesZeroForRestore(t *testing.T) {
	runner := &fakeRunner{}
	adapter := NewWithRunner(runner)
	if err := adapter.SetSleepDisabled(context.Background(), false); err != nil {
		t.Fatal(err)
	}
	want := []string{"-n", "/usr/bin/pmset", "-a", "disablesleep", "0"}
	if !reflect.DeepEqual(runner.args, want) {
		t.Fatalf("restore command args = %#v, want %#v", runner.args, want)
	}
}

func TestStopAssertionSignalsOnlyVerifiedCaffeinateProcess(t *testing.T) {
	runner := &fakeRunner{responses: map[string][]byte{
		"/bin/ps -p 812 -o comm=":           []byte("/usr/bin/caffeinate\n"),
		"/bin/ps -p 812 -o lstart=":         []byte("Fri Nov 20 10:00:00 2026\n"),
		"/usr/sbin/sysctl -n kern.boottime": []byte("{ sec = 1763650800, usec = 0 }\n"),
	}}
	var signaledPID int
	var signaled syscall.Signal
	adapter := NewWithRunnerAndSignaler(runner, func(pid int, signal syscall.Signal) error {
		signaledPID, signaled = pid, signal
		return nil
	})
	err := adapter.StopAssertion(domain.ProcessID{PID: 812, StartTime: "Fri Nov 20 10:00:00 2026", BootID: "{ sec = 1763650800, usec = 0 }"})
	if err != nil {
		t.Fatal(err)
	}
	if signaledPID != 812 || signaled != syscall.SIGTERM {
		t.Fatalf("signal target = %d %v, want validated caffeinate PID 812", signaledPID, signaled)
	}
}

func TestStopAssertionNeverSignalsAnUnrelatedPID(t *testing.T) {
	runner := &fakeRunner{responses: map[string][]byte{
		"/bin/ps -p 812 -o comm=":           []byte("/Applications/Other.app/Contents/MacOS/Other\n"),
		"/bin/ps -p 812 -o lstart=":         []byte("Fri Nov 20 10:00:00 2026\n"),
		"/usr/sbin/sysctl -n kern.boottime": []byte("boot\n"),
	}}
	signaled := false
	adapter := NewWithRunnerAndSignaler(runner, func(int, syscall.Signal) error { signaled = true; return nil })
	err := adapter.StopAssertion(domain.ProcessID{PID: 812, StartTime: "Fri Nov 20 10:00:00 2026", BootID: "boot"})
	if err == nil || signaled {
		t.Fatalf("unrelated PID stop error = %v; signaled = %v", err, signaled)
	}
}

type fakeRunner struct {
	path      string
	args      []string
	output    []byte
	err       error
	responses map[string][]byte
}

func (f *fakeRunner) Run(_ context.Context, path string, args ...string) ([]byte, error) {
	f.path = path
	f.args = append([]string(nil), args...)
	key := path + " " + strings.Join(args, " ")
	if output, ok := f.responses[key]; ok {
		return output, f.err
	}
	return f.output, f.err
}
