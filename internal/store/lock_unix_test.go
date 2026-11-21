//go:build darwin || linux

package store

import (
	"context"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func TestStateLockDescriptorIsCloseOnExec(t *testing.T) {
	stateStore, err := Open(filepath.Join(t.TempDir(), "awake"))
	if err != nil {
		t.Fatal(err)
	}
	lock, err := acquireLock(context.Background(), filepath.Join(stateStore.dir, "state.lock"), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Close()

	flags, _, errno := syscall.Syscall(syscall.SYS_FCNTL, lock.Fd(), syscall.F_GETFD, 0)
	if errno != 0 {
		t.Fatalf("read lock descriptor flags: %v", errno)
	}
	if flags&syscall.FD_CLOEXEC == 0 {
		t.Fatal("state lock descriptor is inherited by child processes; F_CLOEXEC is required")
	}
}
