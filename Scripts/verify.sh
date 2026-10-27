#!/bin/bash
# Checks that NoSleep does what it says on this Mac, against the real system:
# pmset, sudo, launchd, the audio mute. Prints PASS or FAIL per check.
#
#   Scripts/verify.sh        everything that needs no hands, about 3 minutes
#   Scripts/verify.sh lid    the lid test: close the lid when asked
#
# Builds and runs the debug app, which starts a session on its own when
# NOSLEEP_START=<seconds> is set. Sessions it starts land in the panel's
# activity log like any other. Leaves the Mac as it found it: sleep on, Low
# Power Mode and the mute as they were, NoSleep running again.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DOMAIN=dev.intuito.nosleep
PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
check() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
section() { printf '\n%s\n' "$1"; }

sleep_disabled() { pmset -g | awk '/SleepDisabled/ {print $2}'; }
low_power() { pmset -g | awk '/lowpowermode/ {print $2}'; }
muted() { osascript -e 'output muted of (get volume settings)'; }
pref() { defaults read "$DOMAIN" "$1" 2>/dev/null; }
app_pid() { pgrep -x NoSleep; }
lid_closed() { ioreg -r -k AppleClamshellState -d 1 | grep -q '"AppleClamshellState" = Yes'; }
lid_open() { ! lid_closed; }

# The panel's activity log: JSON in a data value, so through plutil and base64.
log_since() {
	defaults export "$DOMAIN" - 2>/dev/null | plutil -extract log raw -o - - 2>/dev/null | base64 -d 2>/dev/null |
		python3 -c '
import json, sys
since = float(sys.argv[1])
# Foundation encodes dates as seconds since 2001-01-01.
for e in json.load(sys.stdin):
    if e["at"] + 978307200 >= since: print(e["title"], "|", e.get("detail", ""))
' "$1" 2>/dev/null
}

# Polls `$@` every second for up to $1 seconds.
within() {
	local seconds="$1"; shift
	for _ in $(seq "$seconds"); do "$@" && return 0; sleep 1; done
	return 1
}
is() { [ "$($1)" = "$2" ]; }
gone() { ! app_pid >/dev/null; }
# What runs without a password: the NOPASSWD entries of `sudo -l`, one per line.
# (`sudo -l <command>` can't tell: an admin's password rule allows everything.)
passwordless() { sudo -n -l 2>/dev/null | sed -n 's/.*NOPASSWD: *//p' | tr ',' '\n' | sed 's/^ *//; s/ *$//'; }
allowed() { passwordless | grep -qxF "/usr/bin/pmset $*"; }
refused() { ! allowed "$@"; }
agent_loaded() { launchctl print "gui/$(id -u)/dev.intuito.nosleep.backstop" >/dev/null 2>&1; }
# pmset's own log: any entry of type Sleep since the given epoch second.
slept_since() {
	pmset -g log | awk -v s="$(date -r "$1" '+%Y-%m-%d %H:%M:%S')" '$1 " " $2 >= s && $4 == "Sleep" { found = 1 } END { exit !found }'
}
never_slept_since() { ! slept_since "$1"; }
# No line in the beat file with the lid shut and $2 in column $1.
never_while_closed() { ! awk -v c="$1" -v v="$2" '$2 == "closed" && $c == v { found = 1 } END { exit !found }' "$BEATS"; }

launch() {
	pkill -x NoSleep; within 10 gone
	if [ -n "${1:-}" ]; then open --env "NOSLEEP_START=$1" "$APP"; else open "$APP"; fi
	within 10 app_pid >/dev/null
}

# --- Before anything changes ---------------------------------------------

if [ "$(sleep_disabled)" = 1 ]; then
	echo "Sleep is already off (a session is running). Switch it back on, then run this again."
	exit 1
fi
LOW_POWER_BEFORE="$(low_power)"
MUTED_BEFORE="$(muted)"

restore() {
	pkill -x NoSleep; within 10 gone
	[ "$(sleep_disabled)" = 1 ] && sudo -n /usr/bin/pmset -a disablesleep 0
	[ "$(low_power)" != "$LOW_POWER_BEFORE" ] && sudo -n /usr/bin/pmset -a lowpowermode "$LOW_POWER_BEFORE"
	osascript -e "set volume output muted $MUTED_BEFORE"
	defaults write "$DOMAIN" lowPowerOwned -bool false
	defaults write "$DOMAIN" mutedByUs -bool false
	open "$APP"
}

command -v notch >/dev/null && notch progress "NoSleep verify" --detail "building"
APP="$(./Scripts/bundle.sh debug 2>/dev/null)" || { echo "Build failed: run Scripts/bundle.sh debug"; exit 1; }
trap restore EXIT

# --- The lid test, with hands ----------------------------------------------

if [ "${1:-}" = lid ]; then
	BEATS="$(mktemp)"
	START=$(date +%s)
	section "Lid test"
	check "session starts" launch 1800
	check "sleep is off" within 10 is sleep_disabled 1
	( while :; do printf '%s %s %s %s\n' "$(date +%s)" "$(lid_closed && echo closed || echo open)" "$(muted)" "$(low_power)" >> "$BEATS"; sleep 5; done ) &
	BEATER=$!
	# Waits on the lid itself rather than on Return, so it also runs where
	# there is no terminal to type into, such as a `!` command in Claude Code.
	echo
	echo "  Close the lid now (within 5 minutes). Open it again after 2 minutes or more."
	command -v notch >/dev/null && notch progress "NoSleep verify" --detail "close the lid now"
	if within 300 lid_closed; then
		command -v notch >/dev/null && notch progress "NoSleep verify" --detail "lid shut, open after 2 min"
		within 1800 lid_open
	fi
	sleep 6
	kill "$BEATER"; wait "$BEATER" 2>/dev/null
	CLOSED=$(grep -c ' closed ' "$BEATS")
	GAP=$(awk 'NR > 1 && $1 - last > max { max = $1 - last } { last = $1 } END { print max + 0 }' "$BEATS")
	check "the lid was shut for 2 minutes or more ($((CLOSED * 5)) s seen)" [ "$CLOSED" -ge 24 ]
	if [ "$CLOSED" = 0 ]; then
		echo "  The lid never closed, so there is nothing to check. Run it again."
		exit 1
	fi
	check "the Mac never slept: longest gap between 5 s beats was ${GAP} s" [ "$GAP" -le 15 ]
	check "no sleep in pmset's log" never_slept_since "$START"
	check "audio was muted while the lid was shut" never_while_closed 3 false
	check "Low Power Mode was on while the lid was shut" never_while_closed 4 0
	check "audio unmuted after the lid opened" within 10 is muted "$MUTED_BEFORE"
	LOG="$(log_since "$START")"
	check "activity log: lid closed, display off" grep -q 'Lid closed .*display off' <<<"$LOG"
	check "activity log: lid opened" grep -q 'Lid opened' <<<"$LOG"
	rm -f "$BEATS"
	section "$PASSED passed, $FAILED failed"
	command -v notch >/dev/null && notch done "NoSleep verify" --detail "lid: $PASSED passed, $FAILED failed"
	exit $((FAILED > 0))
fi

# --- Hands-free checks -----------------------------------------------------

section "Unit tests"
check "swift test" bash -c 'swift test >/dev/null 2>&1'

section "Sudo rule: exactly the five commands, nothing else"
for allowed in "-a disablesleep 0" "-a disablesleep 1" "sleepnow" "-a lowpowermode 0" "-a lowpowermode 1"; do
	# `sudo -l <command>` asks whether the command is allowed, without running it.
	check "allowed: pmset $allowed" allowed $allowed
done
for refused in "-a disablesleep 2" "-a hibernatemode 0" "-a sleep 0"; do
	check "refused: pmset $refused" refused $refused
done
check "nothing else runs without a password ($(passwordless | wc -l | tr -d ' ') entries)" [ "$(passwordless | wc -l | tr -d ' ')" = 5 ]

section "Backstop agent"
check "loaded in launchd" agent_loaded
check "points at this build" grep -q "$APP/Contents/MacOS/NoSleep" "$HOME/Library/LaunchAgents/dev.intuito.nosleep.backstop.plist"

section "Session with a 20 s timer"
command -v notch >/dev/null && notch progress "NoSleep verify" --detail "timer"
T=$(date +%s)
check "app launches and starts a session" launch 20
check "sleep is off" within 10 is sleep_disabled 1
check "the session is marked as ours" within 5 is "pref ownsSession" 1
PID=$(app_pid)
# top's IDLEW is a running total, so the rate comes from the first and last of
# 6 samples 2 s apart. The first CPU sample is meaningless; the last one counts.
TOP=$(top -l 6 -s 2 -pid "$PID" -stats cpu,mem,idlew | awk '$1 ~ /^[0-9.]+$/ { n++; gsub(/\+/, ""); if (n == 1) first = $3; cpu = $1; mem = $2; wake = $3 } END { printf "%s %s %.1f", cpu, mem, (wake - first) / 10 }')
read -r CPU MEM WAKE <<<"$TOP"
check "CPU in a session under 2% (${CPU}%)" awk -v c="$CPU" 'BEGIN { exit !(c < 2) }'
check "memory under 150 MB (${MEM})" awk -v m="$MEM" 'BEGIN { n = m + 0; if (m ~ /G/) n *= 1024; if (m ~ /K/) n /= 1024; exit !(n < 150) }'
check "idle wakeups under 5 a second (${WAKE}/s)" awk -v w="$WAKE" 'BEGIN { exit !(w < 5) }'
check "timer switches sleep back on" within 30 is sleep_disabled 0
check "activity log: kept awake, then timer ran out" bash -c "log=\$(cat); grep -q 'Kept awake' <<<\"\$log\" && grep -q 'timer ran out' <<<\"\$log\"" <<<"$(log_since "$T")"

section "Quit (SIGTERM) mid-session"
check "session starts" launch 600
check "sleep is off" within 10 is sleep_disabled 1
pkill -TERM -x NoSleep
check "app quits" within 10 gone
check "sleep is back on at once" is sleep_disabled 0

section "Crash mid-session: the backstop cleans up within a minute"
command -v notch >/dev/null && notch progress "NoSleep verify" --detail "backstop, up to 80 s"
T=$(date +%s)
check "session starts" launch 600
check "sleep is off" within 10 is sleep_disabled 1
# What a closed lid would have left behind, set by hand: the lid can't be
# closed from a script.
if [ "$LOW_POWER_BEFORE" = 0 ]; then
	sudo -n /usr/bin/pmset -a lowpowermode 1 && defaults write "$DOMAIN" lowPowerOwned -bool true
fi
if [ "$MUTED_BEFORE" = false ]; then
	osascript -e 'set volume output muted true' && defaults write "$DOMAIN" mutedByUs -bool true
fi
pkill -KILL -x NoSleep
within 5 gone
check "still off right after the crash (nothing else restored it)" is sleep_disabled 1
check "sleep back on within 80 s" within 80 is sleep_disabled 0
if [ "$LOW_POWER_BEFORE" = 0 ]; then check "Low Power Mode off again" within 5 is low_power 0; fi
if [ "$MUTED_BEFORE" = false ]; then check "audio unmuted again" within 5 is muted false; fi
check "activity log: recovered after NoSleep stopped" grep -q 'Recovered after NoSleep stopped' <<<"$(log_since "$T")"

section "Panel renders in every state"
SNAPS="$(mktemp -d)"
NOSLEEP_SNAPSHOT_DIR="$SNAPS" "$APP/Contents/MacOS/NoSleep" >/dev/null 2>&1
COUNT=$(find "$SNAPS" -name '*.png' -size +1k | wc -l | tr -d ' ')
check "snapshots written ($COUNT PNGs)" [ "$COUNT" -gt 0 ]
rm -rf "$SNAPS"

section "$PASSED passed, $FAILED failed"
command -v notch >/dev/null && notch done "NoSleep verify" --detail "$PASSED passed, $FAILED failed"
exit $((FAILED > 0))
