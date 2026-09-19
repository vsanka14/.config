#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
engine=$plugin_dir/bin/agent-radar
temp_dir=$(mktemp -d)
server=agent-radar-popup-$$
trap 'tmux -L "$server" kill-server 2>/dev/null || true; rm -rf "$temp_dir"' EXIT

mkdir -p "$temp_dir/bin" "$temp_dir/runtime" "$temp_dir/state"
cat >"$temp_dir/panes" <<'EOF'
%1	test	1	1	100	Live Agent - GitHub Copilot
EOF
cat >"$temp_dir/processes" <<'EOF'
100 1 bash
101 100 copilot
EOF
printf 'Working · esc interrupt\n' >"$temp_dir/capture"

cat >"$temp_dir/bin/fake-tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) cat "$FIXTURE_DIR/panes" ;;
  list-sessions)
    printf '100\ttest\n'
    ;;
  capture-pane) cat "$FIXTURE_DIR/capture" ;;
  switch-client|select-pane|refresh-client|run-shell) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$temp_dir/bin/fake-tmux"

now=$(date +%s)
jq -n --argjson now "$now" \
  '{pane_id:"%1", session_id:"test", status:"working", event:"preToolUse",
    updated_at:"test", updated_epoch:$now}' >"$temp_dir/state/1.json"

tmux -L "$server" -f /dev/null new-session -d -s popup \
  "env FIXTURE_DIR=$(printf '%q' "$temp_dir") TMPDIR=$(printf '%q' "$temp_dir/runtime") \
    TMUX_AGENT_ENGINE_TMUX_BIN=$(printf '%q' "$temp_dir/bin/fake-tmux") \
    TMUX_AGENT_ENGINE_PS_FILE=$(printf '%q' "$temp_dir/processes") \
    AGENT_RADAR_STATE_DIR=$(printf '%q' "$temp_dir/state") NO_COLOR=1 \
    $(printf '%q' "$engine") 2>$(printf '%q' "$temp_dir/popup-error")"

socket=
attempt=0
while [ -z "$socket" ] && [ "$attempt" -lt 60 ]; do
  registration=$(find "$temp_dir/state/.popups" -type f -name '[0-9]*' -print -quit 2>/dev/null || true)
  if [ -n "$registration" ]; then
    IFS= read -r socket <"$registration" || socket=
    [ -S "$socket" ] || socket=
  fi
  [ -n "$socket" ] || sleep 0.05
  attempt=$((attempt + 1))
done
[ -n "$socket" ] || {
  printf 'not ok - popup did not create its refresh socket\n' >&2
  cat "$temp_dir/popup-error" >&2 2>/dev/null || true
  exit 1
}

wait_for_text() {
  local expected=$1 tries=0
  while [ "$tries" -lt 40 ]; do
    if curl -fsS --unix-socket "$socket" http://localhost 2>/dev/null |
       jq -e --arg expected "$expected" \
         'any(.matches[]?; .text | contains($expected))' >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
    tries=$((tries + 1))
  done
  return 1
}

wait_for_text working || {
  printf 'not ok - popup did not render initial working state\n' >&2
  exit 1
}

printf 'Do you want to allow this command?\nAllow once\n' >"$temp_dir/capture"
jq -n --argjson now "$now" \
  '{pane_id:"%1", session_id:"test", status:"awaiting", event:"permissionRequest",
    updated_at:"test", updated_epoch:$now}' >"$temp_dir/state/1.json"

FIXTURE_DIR="$temp_dir" \
TMUX_AGENT_ENGINE_TMUX_BIN="$temp_dir/bin/fake-tmux" \
TMUX_AGENT_ENGINE_PS_FILE="$temp_dir/processes" \
AGENT_RADAR_STATE_DIR="$temp_dir/state" \
AGENT_RADAR_NOTIFY=0 \
"$engine" --refresh --notify

wait_for_text awaiting || {
  printf 'not ok - open popup did not reload awaiting state\n' >&2
  exit 1
}

owner_pid=$(sed -n '2p' "$registration")
kill -KILL "$owner_pid"
attempt=0
while kill -0 "$owner_pid" 2>/dev/null && [ "$attempt" -lt 40 ]; do
  sleep 0.05
  attempt=$((attempt + 1))
done

FIXTURE_DIR="$temp_dir" \
TMUX_AGENT_ENGINE_TMUX_BIN="$temp_dir/bin/fake-tmux" \
TMUX_AGENT_ENGINE_PS_FILE="$temp_dir/processes" \
AGENT_RADAR_STATE_DIR="$temp_dir/state" \
AGENT_RADAR_NOTIFY=0 \
"$engine" --refresh --notify

attempt=0
while { [ -S "$socket" ] ||
        find "$temp_dir/state/.popups" -type f -name '[0-9]*' -print -quit 2>/dev/null |
          grep -q .; } && [ "$attempt" -lt 40 ]; do
  sleep 0.05
  attempt=$((attempt + 1))
done
[ ! -S "$socket" ] || {
  printf 'not ok - popup socket leaked after exit\n' >&2
  exit 1
}
if find "$temp_dir/state/.popups" -type f -name '[0-9]*' -print -quit 2>/dev/null | grep -q .; then
  printf 'not ok - popup registration leaked after exit\n' >&2
  exit 1
fi

printf 'ok - agent radar live popup refresh\n'
