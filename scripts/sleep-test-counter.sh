#!/usr/bin/env bash
# sleep-test-counter.sh - Simple counter to verify macOS sleep prevention
# Usage:
#   ./scripts/sleep-test-counter.sh [duration_in_seconds]
#
# Examples:
#   ./scripts/sleep-test-counter.sh 60           # Runs for 60 seconds
#   ./scripts/sleep-test-counter.sh              # Runs until Ctrl+C
#   awake run ./scripts/sleep-test-counter.sh 60 # Wraps with Awake automatically

set -u

TOTAL_SECONDS="${1:-0}"
LOG_FILE="/tmp/awake-counter.log"

echo "=========================================================="
echo "  ⏱️  Awake Sleep Prevention Test Counter"
echo "=========================================================="
echo "Log file: ${LOG_FILE}"
if [ "${TOTAL_SECONDS}" -gt 0 ]; then
  echo "Mode: Auto-stop after ${TOTAL_SECONDS} seconds"
else
  echo "Mode: Continuous (Press Ctrl+C to stop)"
fi
echo "Tip: Check if timestamp jumps. If Mac sleeps, a gap will appear."
echo "=========================================================="
echo ""

# Reset log file
echo "# Awake Sleep Test Counter Log - Started at $(date)" > "${LOG_FILE}"

COUNT=0
SLEEP_COUNT=0
LAST_EPOCH=$(date +%s)
START_TIME=$(date +"%T")

cleanup() {
  echo ""
  echo "=========================================================="
  echo "  🏁 Test Summary"
  echo "=========================================================="
  echo "Started at:     ${START_TIME}"
  echo "Ended at:       $(date +"%T")"
  echo "Total Ticks:    ${COUNT} seconds"
  if [ "${SLEEP_COUNT}" -gt 0 ]; then
    echo "Sleep Pauses:   ⚠️  ${SLEEP_COUNT} sleep freeze(s) detected!"
    echo "Result:         ❌ System went to sleep during test."
  else
    echo "Sleep Pauses:   ✅ 0 (Continuous execution without freezing)"
    echo "Result:         🎉 Mac remained AWAKE throughout the test!"
  fi
  echo "Detailed Log:   ${LOG_FILE}"
  echo "=========================================================="
  exit 0
}

trap cleanup INT TERM

while true; do
  sleep 1
  COUNT=$((COUNT + 1))
  NOW_EPOCH=$(date +%s)
  NOW_TIME=$(date +"%T")
  DIFF=$((NOW_EPOCH - LAST_EPOCH))

  if [ "${DIFF}" -ge 3 ]; then
    GAP=$((DIFF - 1))
    SLEEP_COUNT=$((SLEEP_COUNT + 1))
    MSG="[${NOW_TIME}] ⚠️  SLEEP DETECTED! Gap of ${GAP}s (Tick #${COUNT})"
    echo -e "\033[1;31m${MSG}\033[0m"
    echo "${MSG}" >> "${LOG_FILE}"
  else
    # Check if caffeinate or Awake holds assertion
    ASSERTION_INFO=""
    if pgrep -x "caffeinate" >/dev/null 2>&1; then
      ASSERTION_INFO="[caffeinate active]"
    fi
    MSG="[${NOW_TIME}] Tick #${COUNT} | Awake OK ${ASSERTION_INFO}"
    echo "${MSG}"
    echo "${MSG}" >> "${LOG_FILE}"
  fi

  LAST_EPOCH="${NOW_EPOCH}"

  if [ "${TOTAL_SECONDS}" -gt 0 ] && [ "${COUNT}" -ge "${TOTAL_SECONDS}" ]; then
    break
  fi
done

cleanup
