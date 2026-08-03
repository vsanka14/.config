#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
hook=$plugin_dir/bin/agent-radar-hook
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

cat >"$temp_dir/tmux" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$temp_dir/tmux"

marker=$temp_dir/notified
printf '%s\n' '{"hookName":"preToolUse","sessionId":"test"}' |
  AGENT_RADAR_STATE_DIR="$temp_dir/state" \
  AGENT_RADAR_TMUX_BIN="$temp_dir/tmux" \
  AGENT_RADAR_ON_CHANGE="printf changed > $(printf '%q' "$marker")" \
  TMUX_PANE='%7' \
  "$hook"

attempt=0
while [ ! -f "$marker" ] && [ "$attempt" -lt 20 ]; do
  sleep 0.05
  attempt=$((attempt + 1))
done

[ "$(cat "$marker" 2>/dev/null)" = changed ] || {
  printf 'not ok - on-change callback did not run\n' >&2
  exit 1
}

printf 'ok - agent radar notification callback\n'
