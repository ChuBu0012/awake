//go:build windows

package store

import (
	"context"
	"fmt"
	"os"
	"time"
)

func acquireLock(context.Context, string, time.Duration) (*os.File, error) {
	return nil, fmt.Errorf("Windows state locking is not implemented in the macOS-first release")
}

func ownedByCurrentUser(os.FileInfo) bool { return true }
