#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
setup=$plugin_dir/bin/agent-radar-setup
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

legacy=$temp_dir/copilot/agent-status
state=$temp_dir/state/agent-radar
mkdir -p "$legacy"
printf '%s\n' \
  '{"pane_id":"%7","status":"working","updated_epoch":300}' \
  >"$legacy/7.json"
printf '%s\n' '{"prompt":"must not migrate"}' >"$legacy/8.json"
printf '%s\n' \
  '{"pane_id":"%9","status":"idle","updated_epoch":100}' \
  >"$legacy/9.json"
mkdir -p "$state"
printf '%s\n' \
  '{"pane_id":"%9","status":"working","updated_epoch":200}' \
  >"$state/9.json"

HOME="$temp_dir/home" \
COPILOT_HOME="$temp_dir/copilot" \
AGENT_RADAR_STATE_DIR="$state" \
"$setup" install >/dev/null

[ -f "$state/7.json" ] || {
  printf 'not ok - valid legacy state was not migrated\n' >&2
  exit 1
}
[ ! -e "$state/8.json" ] || {
  printf 'not ok - invalid legacy state was migrated\n' >&2
  exit 1
}
[ "$(jq -r '.status' "$state/9.json")" = working ] || {
  printf 'not ok - newer destination state was overwritten\n' >&2
  exit 1
}
[ ! -e "$legacy/7.json" ] || {
  printf 'not ok - legacy state was not cleaned\n' >&2
  exit 1
}

descriptor=$temp_dir/copilot/hooks/tmux-agent-status.json
jq -e --arg hook "$plugin_dir/bin/agent-radar-hook" '
  .version == 1
  and ([.hooks[][] | .command] | length == 12)
  and ((.hooks | keys) == [
    "agentStop",
    "errorOccurred",
    "notification",
    "permissionRequest",
    "postToolUse",
    "postToolUseFailure",
    "preToolUse",
    "sessionEnd",
    "sessionStart",
    "subagentStart",
    "subagentStop",
    "userPromptSubmitted"
  ])
  and (.hooks.notification[0].matcher == "permission_prompt|elicitation_dialog")
  and all(.hooks[][]; (.command | contains($hook + " ")))
' "$descriptor" >/dev/null || {
  printf 'not ok - generated hook descriptor is invalid\n' >&2
  exit 1
}

HOME="$temp_dir/home" \
COPILOT_HOME="$temp_dir/copilot" \
AGENT_RADAR_STATE_DIR="$state" \
"$setup" doctor >/dev/null

custom_state=$temp_dir/custom-state
custom_copilot=$temp_dir/custom-copilot
mkdir -p "$temp_dir/fake-bin"
cat >"$temp_dir/fake-bin/tmux" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = show-option ]; then
  printf '%s\n' "$custom_state"
fi
EOF
chmod +x "$temp_dir/fake-bin/tmux"
HOME="$temp_dir/home" \
COPILOT_HOME="$custom_copilot" \
PATH="$temp_dir/fake-bin:$PATH" \
"$setup" install >/dev/null
jq -e --arg state "$custom_state" '
  all(.hooks[][]; (.command | startswith("env AGENT_RADAR_STATE_DIR=" + $state + " ")))
' "$custom_copilot/hooks/tmux-agent-status.json" >/dev/null || {
  printf 'not ok - tmux state directory option was not propagated\n' >&2
  exit 1
}

mkdir -p "$temp_dir/symlink-target"
ln -s "$temp_dir/symlink-target" "$temp_dir/symlink-state"
if HOME="$temp_dir/home" \
   COPILOT_HOME="$temp_dir/other-copilot" \
   AGENT_RADAR_STATE_DIR="$temp_dir/symlink-state" \
   "$setup" install >/dev/null 2>&1; then
  printf 'not ok - symlinked state directory was accepted\n' >&2
  exit 1
fi

printf 'ok - agent radar setup\n'
