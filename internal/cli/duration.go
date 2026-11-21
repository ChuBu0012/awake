package cli

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

const maxDuration = 365 * 24 * time.Hour

// ParseDuration accepts an unsigned integer followed by s, m, or h. A zero
// duration or "indefinite" means no automatic expiry.
func ParseDuration(input string) (time.Duration, error) {
	if input == "indefinite" || input == "infinite" || input == "0" {
		return 0, nil
	}
	if input == "" || strings.TrimSpace(input) != input {
		return 0, fmt.Errorf("duration must be an unsigned integer with s, m, or h")
	}
	unit := time.Second
	last := input[len(input)-1]
	switch last {
	case 's', 'S':
		input = input[:len(input)-1]
	case 'm', 'M':
		unit = time.Minute
		input = input[:len(input)-1]
	case 'h', 'H':
		unit = time.Hour
		input = input[:len(input)-1]
	}
	if input == "" {
		return 0, fmt.Errorf("duration value is required")
	}
	for _, char := range input {
		if char < '0' || char > '9' {
			return 0, fmt.Errorf("duration must contain only digits and one supported unit")
		}
	}
	value, err := strconv.ParseUint(input, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid duration value: %w", err)
	}
	if value > uint64(maxDuration/unit) {
		return 0, fmt.Errorf("duration exceeds the maximum of 365 days")
	}
	duration := time.Duration(value) * unit
	if duration > maxDuration {
		return 0, fmt.Errorf("duration exceeds the maximum of 365 days")
	}
	return duration, nil
}
