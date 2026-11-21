package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	"awake/internal/cli"
	"awake/internal/engine"
	"awake/internal/platform/macos"
	"awake/internal/store"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Awake: resolve home directory: %v\n", err)
		return 2
	}
	dir, err := store.DefaultDirectory(home, os.Getenv("XDG_CONFIG_HOME"))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Awake: resolve state directory: %v\n", err)
		return 2
	}
	stateStore, err := store.Open(dir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Awake: open state: %v\n", err)
		return 2
	}
	adapter := macos.New()
	coordinator := engine.New(stateStore, adapter, nil)
	application := cli.New(coordinator, adapter, commandRunner{}, os.Stdout, os.Stderr)
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := application.Run(ctx, args); err != nil {
		var exitErr cli.ExitError
		if errors.As(err, &exitErr) {
			return exitErr.Code
		}
		if errors.Is(err, context.Canceled) {
			return 130
		}
		fmt.Fprintf(os.Stderr, "Awake: %v\n", err)
		return 2
	}
	return 0
}

type commandRunner struct{}

func (commandRunner) Run(ctx context.Context, args []string) (int, error) {
	if len(args) == 0 || filepath.Base(args[0]) == "." || strings.TrimSpace(args[0]) == "" {
		return 2, fmt.Errorf("invalid child command")
	}
	command := exec.CommandContext(ctx, args[0], args[1:]...)
	command.Stdin = os.Stdin
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return exitErr.ExitCode(), nil
		}
		return 2, err
	}
	return 0, nil
}
