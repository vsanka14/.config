#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
hook=$repo_dir/bin/tmux-agent-status
picker=$repo_dir/bin/tmux-agent-picker
descriptor=${COPILOT_HOOK_DESCRIPTOR:-$HOME/.copilot/hooks/tmux-agent-status.json}
descriptor_command='$HOME/.config/bin/tmux-agent-status'
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected=$1 actual=$2 message=$3
  [ "$actual" = "$expected" ] || fail "$message: expected '$expected', got '$actual'"
}

run_hook() {
  local event=$1 payload=${2:-}
  printf '{"hookName":"%s","sessionId":"session-1"%s}' "$event" "$payload" |
    COPILOT_HOME="$temp_dir/copilot-home" TMUX_PANE='%7' \
      TMUX_AGENT_STATUS_REFRESH=0 "$hook"
}

state_value() {
  jq -r "$1" "$temp_dir/copilot-home/agent-status/7.json"
}

run_hook sessionStart
assert_eq idle "$(state_value .status)" "sessionStart status"
run_hook userPromptSubmitted ',"prompt":"must not persist"'
assert_eq working "$(state_value .status)" "prompt status"
printf '{}' |
  COPILOT_HOME="$temp_dir/copilot-home" TMUX_PANE='%7' "$hook" sessionStart
assert_eq working "$(state_value .status)" "late sessionStart preserves working"
run_hook permissionRequest ',"toolInput":{"secret":"must not persist"}'
assert_eq awaiting "$(state_value .status)" "permission status"
run_hook preToolUse ',"toolName":"bash","toolInput":{"secret":"must not persist"}'
assert_eq working "$(state_value .status)" "preToolUse clears awaiting"
assert_eq bash "$(state_value .tool_name)" "tool metadata"
run_hook subagentStart ',"agentDisplayName":"test-agent"'
assert_eq working "$(state_value .status)" "subagent keeps parent working"
assert_eq test-agent "$(state_value .subagent_name)" "subagent metadata"
run_hook agentStop ',"stopReason":"end_turn"'
assert_eq idle "$(state_value .status)" "agentStop status"
assert_eq done "$(state_value '.flash.kind')" "agentStop after working flashes done"

# Isolated flash-transition coverage on a separate pane.
flash_home="$temp_dir/copilot-home"
flash_run() {
  local event=$1
  printf '{"hookName":"%s","sessionId":"flash"}' "$event" |
    COPILOT_HOME="$flash_home" TMUX_PANE='%20' TMUX_AGENT_STATUS_REFRESH=0 "$hook"
}
flash_val() { jq -r "$1 // \"null\"" "$flash_home/agent-status/20.json"; }

flash_run sessionStart
assert_eq null "$(flash_val '.flash.kind')" "fresh sessionStart does not flash done"
flash_run preToolUse
flash_run subagentStop
assert_eq working "$(flash_val '.status')" "subagentStop keeps working"
assert_eq null "$(flash_val '.flash.kind')" "subagentStop does not flash done"
flash_run agentStop
assert_eq idle "$(flash_val '.status')" "agentStop settles idle"
assert_eq done "$(flash_val '.flash.kind')" "agentStop after working flashes done (isolated)"
rm -f "$flash_home/agent-status/20.json"

if grep -Eq 'must not persist|toolInput|prompt' "$temp_dir/copilot-home/agent-status/7.json"; then
  fail "state persisted sensitive payload data"
fi
assert_eq 700 "$(stat -f '%Lp' "$temp_dir/copilot-home/agent-status")" "state directory mode"
assert_eq 600 "$(stat -f '%Lp' "$temp_dir/copilot-home/agent-status/7.json")" "state file mode"

run_hook sessionEnd
[ ! -e "$temp_dir/copilot-home/agent-status/7.json" ] || fail "sessionEnd did not remove state"

cat >"$temp_dir/hook-processes" <<'EOF'
700 1 bash
800 700 copilot
900 800 bash
EOF
cat >"$temp_dir/hook-tmux" <<'EOF'
#!/usr/bin/env bash
printf '%%8\t700\n'
EOF
chmod +x "$temp_dir/hook-tmux"
printf '{"hookName":"sessionStart","sessionId":"resolved-session"}' |
  env -u TMUX_PANE \
    COPILOT_HOME="$temp_dir/copilot-home" \
    TMUX_AGENT_STATUS_TMUX_BIN="$temp_dir/hook-tmux" \
    TMUX_AGENT_STATUS_PS_FILE="$temp_dir/hook-processes" \
    TMUX_AGENT_STATUS_PROCESS_PID=900 \
    "$hook"
assert_eq resolved-session \
  "$(jq -r .session_id "$temp_dir/copilot-home/agent-status/8.json")" \
  "pane resolution through Copilot ancestry"

[ -f "$descriptor" ] || fail "missing Copilot hook descriptor: $descriptor"
jq -e --arg command "$descriptor_command" '
  .version == 1
  and ([.hooks[][] | .command] | length == 9)
  and all(.hooks[][]; (.command | startswith($command + " ")))
' "$descriptor" >/dev/null || fail "invalid Copilot hook descriptor"

fixture_dir=$temp_dir/fixtures
state_dir=$temp_dir/picker-state
mkdir -p "$fixture_dir" "$state_dir"

cat >"$fixture_dir/panes" <<'EOF'
%1	alpha	1	1	100	Awaiting Hook - GitHub Copilot
%2	beta	1	2	200	Permission Fallback - GitHub Copilot
%3	gamma	2	1	300	Stale Worker - GitHub Copilot
%4	delta	1	1	400	Unknown Session - GitHub Copilot
%5	excluded	1	1	500	Not Copilot
EOF

cat >"$fixture_dir/processes" <<'EOF'
100 1 bash
101 100 copilot
200 1 zsh
210 200 node
211 210 /opt/bin/copilot
300 1 bash
301 300 copilot
400 1 bash
401 400 copilot
500 1 bash
EOF

cat >"$fixture_dir/capture_1" <<'EOF'
Working · esc interrupt
EOF
cat >"$fixture_dir/capture_2" <<'EOF'
Do you want to allow this command?
Allow once
EOF
cat >"$fixture_dir/capture_3" <<'EOF'
/ commands · ? help
EOF
cat >"$fixture_dir/capture_4" <<'EOF'
unrecognized footer
EOF

cat >"$fixture_dir/fake-tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  list-panes)
    cat "$FIXTURE_DIR/panes"
    ;;
  list-sessions)
    printf '100\talpha\n200\tbeta\n300\tgamma\n400\tdelta\n'
    ;;
  capture-pane)
    pane=
    while [ $# -gt 0 ]; do
      if [ "$1" = -t ]; then
        pane=$2
        break
      fi
      shift
    done
    cat "$FIXTURE_DIR/capture_${pane#%}"
    ;;
  switch-client|select-pane)
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fixture_dir/fake-tmux"

write_state() {
  local pane=$1 status=$2 epoch=$3
  jq -n \
    --arg pane "%$pane" \
    --arg status "$status" \
    --argjson epoch "$epoch" \
    '{pane_id: $pane, session_id: "test", status: $status, event: "test", updated_at: "test", updated_epoch: $epoch}' \
    >"$state_dir/$pane.json"
}

write_state 1 awaiting 2000000000
write_state 2 working 2000000000
write_state 3 working 1999998000
printf '{bad json' >"$state_dir/4.json"
write_state 99 idle 2000000000

rows=$(
  FIXTURE_DIR="$fixture_dir" \
    TMUX_AGENT_PICKER_TMUX_BIN="$fixture_dir/fake-tmux" \
    TMUX_AGENT_PICKER_PS_FILE="$fixture_dir/processes" \
    TMUX_AGENT_PICKER_STATE_DIR="$state_dir" \
    TMUX_AGENT_PICKER_NOW=2000000000 \
    NO_COLOR=1 \
    "$picker" --list
)

assert_eq 4 "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" "eligible pane count"
assert_eq $'1\t%2\tbeta\tbeta:1.2\t⏸ awaiting\tPermission Fallback' \
  "$(printf '%s\n' "$rows" | sed -n '1p' | cut -f1-6)" "permission fallback precedence"
assert_eq $'2\t%1\talpha\talpha:1.1\t⚙ working\tAwaiting Hook' \
  "$(printf '%s\n' "$rows" | sed -n '2p' | cut -f1-6)" "working fallback clears stale awaiting hook"
assert_eq $'4\t%3\tgamma\tgamma:2.1\t✓ idle\tStale Worker' \
  "$(printf '%s\n' "$rows" | sed -n '3p' | cut -f1-6)" "stale state fallback"
assert_eq $'5\t%4\tdelta\tdelta:1.1\t? unknown\tUnknown Session' \
  "$(printf '%s\n' "$rows" | sed -n '4p' | cut -f1-6)" "unknown classification"
assert_eq 'working     alpha:1.1                   Awaiting Hook' \
  "$(printf '%s\n' "$rows" | sed -n '2p' | cut -f7)" "aligned display row"
[ ! -e "$state_dir/99.json" ] || fail "dead pane state was not pruned"

cat >>"$fixture_dir/panes" <<'EOF'
%6	beta	1	3	600	Idle Partner - GitHub Copilot
EOF
cat >>"$fixture_dir/processes" <<'EOF'
600 1 bash
601 600 copilot
EOF
cat >"$fixture_dir/capture_6" <<'EOF'
/ commands · ? help
EOF
write_state 6 idle 2000000000

cat >>"$fixture_dir/panes" <<'EOF'
%7	beta	1	10	700	Tenth Pane - GitHub Copilot
EOF
cat >>"$fixture_dir/processes" <<'EOF'
700 1 bash
701 700 copilot
EOF
cat >"$fixture_dir/capture_7" <<'EOF'
/ commands · ? help
EOF
write_state 7 idle 2000000000

tmux_status=$(
  FIXTURE_DIR="$fixture_dir" \
    TMUX_AGENT_PICKER_TMUX_BIN="$fixture_dir/fake-tmux" \
    TMUX_AGENT_PICKER_PS_FILE="$fixture_dir/processes" \
    TMUX_AGENT_PICKER_STATE_DIR="$state_dir" \
    TMUX_AGENT_PICKER_NOW=2000000000 \
    NO_COLOR=1 \
    "$picker" --tmux-status beta
)
assert_eq '#[fg=#f7768e,bg=#24283b,bold]   #[fg=#f7768e,bold]1.2 #[fg=#9ece6a,nobold]1.3 #[fg=#9ece6a,nobold]1.10 #[bg=#050505,nobold] #[fg=#565f89]● #[fg=#f7768e]◉ #[fg=#565f89]● #[fg=#565f89]● #[default]' \
  "$tmux_status" "tmux status rendering"

cross_session_status=$(
  FIXTURE_DIR="$fixture_dir" \
    TMUX_AGENT_PICKER_TMUX_BIN="$fixture_dir/fake-tmux" \
    TMUX_AGENT_PICKER_PS_FILE="$fixture_dir/processes" \
    TMUX_AGENT_PICKER_STATE_DIR="$state_dir" \
    TMUX_AGENT_PICKER_NOW=2000000000 \
    NO_COLOR=1 \
    "$picker" --tmux-status alpha
)
assert_eq '#[fg=#f7768e,bg=#24283b,bold]   #[fg=#e0af68,bold]1.1 #[bg=#050505,nobold] #[fg=#9ece6a]◉ #[fg=#f7768e]● #[fg=#565f89]● #[fg=#565f89]● #[default]' \
  "$cross_session_status" "cross-session radar rendering"

# Transient completion (done) flash: an idle pane carrying an unexpired
# flash.kind=done renders as rank 3 "done", then decays back to idle.
cat >>"$fixture_dir/panes" <<'EOF'
%8	beta	1	4	800	Finished Task - GitHub Copilot
EOF
cat >>"$fixture_dir/processes" <<'EOF'
800 1 bash
801 800 copilot
EOF
cat >"$fixture_dir/capture_8" <<'EOF'
/ commands · ? help
EOF
jq -n \
  '{pane_id:"%8", session_id:"test", status:"idle", event:"agentStop",
    updated_at:"test", updated_epoch:2000000000,
    flash:{kind:"done", until_epoch:2000000005}}' \
  >"$state_dir/8.json"

done_row=$(
  FIXTURE_DIR="$fixture_dir" \
    TMUX_AGENT_PICKER_TMUX_BIN="$fixture_dir/fake-tmux" \
    TMUX_AGENT_PICKER_PS_FILE="$fixture_dir/processes" \
    TMUX_AGENT_PICKER_STATE_DIR="$state_dir" \
    TMUX_AGENT_PICKER_NOW=2000000000 \
    NO_COLOR=1 \
    "$picker" --list | awk -F '\t' '$2 == "%8" { print $1 "\t" $5 }'
)
assert_eq $'3\t✓ done' "$done_row" "active done flash renders as done"

decayed_row=$(
  FIXTURE_DIR="$fixture_dir" \
    TMUX_AGENT_PICKER_TMUX_BIN="$fixture_dir/fake-tmux" \
    TMUX_AGENT_PICKER_PS_FILE="$fixture_dir/processes" \
    TMUX_AGENT_PICKER_STATE_DIR="$state_dir" \
    TMUX_AGENT_PICKER_NOW=2000000100 \
    NO_COLOR=1 \
    "$picker" --list | awk -F '\t' '$2 == "%8" { print $1 "\t" $5 }'
)
assert_eq $'4\t✓ idle' "$decayed_row" "expired done flash decays to idle"
flash_status=$(
  FIXTURE_DIR="$fixture_dir" \
    TMUX_AGENT_PICKER_TMUX_BIN="$fixture_dir/fake-tmux" \
    TMUX_AGENT_PICKER_PS_FILE="$fixture_dir/processes" \
    TMUX_AGENT_PICKER_STATE_DIR="$state_dir" \
    TMUX_AGENT_PICKER_NOW=2000000000 \
    NO_COLOR=1 \
    "$picker" --tmux-status beta
)
assert_eq '#[fg=#f7768e,bg=#24283b,bold]   #[fg=#f7768e,bold]1.2 #[fg=#9ece6a,nobold]1.3 #[fg=#3fb950,bold]✓1.4 #[fg=#9ece6a,nobold]1.10 #[bg=#050505,nobold] #[fg=#565f89]● #[fg=#f7768e]◉ #[fg=#565f89]● #[fg=#565f89]● #[default]' \
  "$flash_status" "completion flash renders green in the pill"
rm -f "$state_dir/8.json"

# Shared render cache: an enabled run (real clock) writes the cache so
# concurrent status-right expansions can reuse one scan; a pinned-NOW run — as
# the rest of this suite uses — must bypass the cache entirely for determinism.
cache_state_dir=$temp_dir/cache-state
mkdir -p "$cache_state_dir"
FIXTURE_DIR="$fixture_dir" \
  TMUX_AGENT_PICKER_TMUX_BIN="$fixture_dir/fake-tmux" \
  TMUX_AGENT_PICKER_PS_FILE="$fixture_dir/processes" \
  TMUX_AGENT_PICKER_STATE_DIR="$cache_state_dir" \
  TMUX_AGENT_PICKER_CACHE_TTL=3600 \
  NO_COLOR=1 \
  "$picker" --tmux-status beta >/dev/null
[ -f "$cache_state_dir/.tmux-status.cache" ] || fail "enabled cache run did not write cache"

rm -f "$cache_state_dir/.tmux-status.cache"
FIXTURE_DIR="$fixture_dir" \
  TMUX_AGENT_PICKER_TMUX_BIN="$fixture_dir/fake-tmux" \
  TMUX_AGENT_PICKER_PS_FILE="$fixture_dir/processes" \
  TMUX_AGENT_PICKER_STATE_DIR="$cache_state_dir" \
  TMUX_AGENT_PICKER_NOW=2000000000 \
  NO_COLOR=1 \
  "$picker" --tmux-status beta >/dev/null
[ ! -e "$cache_state_dir/.tmux-status.cache" ] || fail "pinned-NOW run must not use the cache"

ask_user_status=$(
  printf '%s\n' \
    'Should I commit the tmux agent picker implementation now?' \
    '❯ 1. Yes, commit all implementation files' \
    '  2. No, leave the changes uncommitted' \
    '↑/↓ to select · enter to confirm · esc to cancel' |
    "$picker" --live-status
)
assert_eq awaiting "$ask_user_status" "ask_user choice prompt classification"

freeform_ask_user_status=$(
  printf '%s\n' \
    '○ Asking user What should I wait for before continuing?' \
    'Question' \
    'What should I wait for before continuing?' \
    '❯ Type your answer...' \
    'enter to submit · esc to cancel' |
    "$picker" --live-status
)
assert_eq awaiting "$freeform_ask_user_status" "ask_user freeform prompt classification"

cat >"$fixture_dir/fzf" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FZF_ARGS_FILE"
sed -n '1p'
EOF
chmod +x "$fixture_dir/fzf"
fzf_args=$temp_dir/fzf-args
FIXTURE_DIR="$fixture_dir" \
  FZF_ARGS_FILE="$fzf_args" \
  PATH="$fixture_dir:$PATH" \
  TMUX_AGENT_PICKER_TMUX_BIN="$fixture_dir/fake-tmux" \
  TMUX_AGENT_PICKER_PS_FILE="$fixture_dir/processes" \
  TMUX_AGENT_PICKER_STATE_DIR="$state_dir" \
  TMUX_AGENT_PICKER_NOW=2000000000 \
  NO_COLOR=1 \
  "$picker"
grep -Fxq -- '--track' "$fzf_args" || fail "fzf tracking was not enabled"
grep -Fxq -- '--with-nth=7' "$fzf_args" || fail "fzf did not use the formatted display field"
grep -Fxq -- '--border-label=  Agents ' "$fzf_args" ||
  fail "fzf border label did not include the tmux icon"
grep -Fxq -- '--preview-window=right,55%,border-left,follow' "$fzf_args" ||
  fail "fzf preview was not placed on the right and pinned to the bottom"
if grep -Eq '^--bind=load:reload' "$fzf_args"; then
  fail "fzf startup still triggers a redundant delayed reload"
fi

cat >"$fixture_dir/preview-tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PREVIEW_ARGS_FILE"
printf '\033[31mred\033[0m\n'
EOF
chmod +x "$fixture_dir/preview-tmux"
preview_args=$temp_dir/preview-args
preview_output=$(
  PREVIEW_ARGS_FILE="$preview_args" \
    TMUX_AGENT_PICKER_TMUX_BIN="$fixture_dir/preview-tmux" \
    "$picker" preview %1
)
grep -Fxq -- '-e' "$preview_args" || fail "tmux preview did not preserve ANSI colors"
assert_eq $'\033[31mred\033[0m' "$preview_output" "preview ANSI output"

printf 'ok - tmux agent picker fixtures\n'
