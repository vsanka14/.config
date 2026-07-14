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
    COPILOT_HOME="$temp_dir/copilot-home" TMUX_PANE='%7' "$hook"
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
/ commands · ? help
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
assert_eq $'1\t%1\talpha\talpha:1.1\t⏸ awaiting\tAwaiting Hook' \
  "$(printf '%s\n' "$rows" | sed -n '1p' | cut -f1-6)" "fresh awaiting classification"
assert_eq $'1\t%2\tbeta\tbeta:1.2\t⏸ awaiting\tPermission Fallback' \
  "$(printf '%s\n' "$rows" | sed -n '2p' | cut -f1-6)" "permission fallback precedence"
assert_eq $'3\t%3\tgamma\tgamma:2.1\t✓ idle\tStale Worker' \
  "$(printf '%s\n' "$rows" | sed -n '3p' | cut -f1-6)" "stale state fallback"
assert_eq $'4\t%4\tdelta\tdelta:1.1\t? unknown\tUnknown Session' \
  "$(printf '%s\n' "$rows" | sed -n '4p' | cut -f1-6)" "unknown classification"
assert_eq 'awaiting    alpha:1.1                   Awaiting Hook' \
  "$(printf '%s\n' "$rows" | sed -n '1p' | cut -f7)" "aligned display row"
[ ! -e "$state_dir/99.json" ] || fail "dead pane state was not pruned"

ask_user_status=$(
  printf '%s\n' \
    'Should I commit the tmux agent picker implementation now?' \
    '❯ 1. Yes, commit all implementation files' \
    '  2. No, leave the changes uncommitted' \
    '↑/↓ to select · enter to confirm · esc to cancel' |
    "$picker" --live-status
)
assert_eq awaiting "$ask_user_status" "ask_user choice prompt classification"

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
grep -Fxq -- '--preview-window=right,55%,border-left' "$fzf_args" ||
  fail "fzf preview was not placed on the right"
grep -Eq '^--bind=load:reload\(sleep 1; .* --list 2>/dev/null \|\| true\)$' "$fzf_args" ||
  fail "fzf periodic reload binding was not configured"

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
