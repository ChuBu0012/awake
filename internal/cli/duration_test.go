package cli

import (
	"testing"
	"time"
)

func TestParseDurationAcceptsSupportedUnits(t *testing.T) {
	cases := map[string]time.Duration{
		"30m":        30 * time.Minute,
		"1H":         time.Hour,
		"45s":        45 * time.Second,
		"90":         90 * time.Second,
		"0":          0,
		"indefinite": 0,
	}
	for input, want := range cases {
		got, err := ParseDuration(input)
		if err != nil || got != want {
			t.Errorf("ParseDuration(%q) = %s, %v; want %s", input, got, err, want)
		}
	}
}

func TestParseDurationRejectsUntrustedOrOverflowingInput(t *testing.T) {
	for _, input := range []string{"-1h", "1h;pmset", "1e9", "999999999999999h", "", " 30m"} {
		if _, err := ParseDuration(input); err == nil {
			t.Errorf("ParseDuration(%q) unexpectedly succeeded", input)
		}
	}
}
