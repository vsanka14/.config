#!/bin/bash

# Single owner of the `agent` menu-bar item. Renders Copilot agent status inline
# as a count-based summary next to the agent icon (no popup):
#   - a completion ("done") shows a transient green count that clears itself when
#     the underlying Agent Radar done flash expires;
#   - awaiting-permission agents show a blocking red count (with a red-tinted
#     item background) that persists until they move on.
# The label collapses the notable sessions into per-kind counts rather than
# listing names, so it stays compact and never overflows the bar no matter how
# many agents are tracked:
#   - awaiting only:     "⏸ N awaiting"
#   - done only:         "✓ M done"
#   - awaiting + done:   "⏸ N awaiting  ✓ M done"
# The item is hidden entirely unless there is a notable agent (awaiting or done);
# idle/working-only agents draw nothing, so the icon only appears when it needs
# attention.
# Agent Radar invokes the configured `@agent-radar-on-change` command on real
# transitions. The notable set + colour are re-derived from its `--notify-lines`
# API (one LINE per session), so this plugin never duplicates pane-scan logic; it
# only counts the lines the engine already emits.
#
# Bash 3.2 (macOS) safe: indexed arrays only, no associative arrays / mapfile.

ITEM=${NAME:-agent}
ENGINE=${AGENT_ENGINE_BIN:-$HOME/.config/tmux/plugins/agent-radar/bin/agent-radar}

# Tokyo Night Moon accents, aligned with the tmux pill/radar colours.
COLOR_AWAITING=0xfff7768e
COLOR_DONE=0xff3fb950
COLOR_OTHER=0xff7dcfff
COLOR_MUTED=0xff636da6
# Item background: neutral by default, red-tinted while blocking (awaiting).
BG_NEUTRAL=0x991e2030
BG_BLOCKING=0x66f7768e

# `#rrggbb` (engine output) -> `0xffrrggbb` (SketchyBar).
hex_to_color() {
  local h=${1#\#}
  case "$h" in
    [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) printf '0xff%s' "$h" ;;
    *) printf '%s' "$COLOR_OTHER" ;;
  esac
}

hide_item() {
  sketchybar --set "$ITEM" drawing=off label.drawing=off >/dev/null 2>&1
}

[ -x "$ENGINE" ] || { hide_item; exit 0; }

runtime_command=
if [ -z "${AGENT_ENGINE_BIN:-}" ] &&
   [ -z "${AGENT_RADAR_STATE_DIR:-}" ] &&
   command -v tmux >/dev/null 2>&1; then
  runtime_command=$(tmux show-option -gqv @agent-radar-runtime-command 2>/dev/null) ||
    runtime_command=
fi
case "$runtime_command" in
  env\ */agent-radar)
    out=$(/bin/sh -c "$runtime_command --notify-lines" 2>/dev/null)
    ;;
  *)
    out=$("$ENGINE" --notify-lines 2>/dev/null)
    ;;
esac
if [ -z "$out" ]; then
  hide_item
  exit 0
fi

color=
awaiting_count=0
done_count=0
while IFS=$'\t' read -r tag field_a field_b; do
  case "$tag" in
    COLOR) color=$field_a ;;
    LINE)
      case "$field_b" in
        awaiting) awaiting_count=$((awaiting_count + 1)) ;;
        done) done_count=$((done_count + 1)) ;;
      esac
      ;;
  esac
done <<EOF
$out
EOF

icon_color=$(hex_to_color "${color:-#7dcfff}")

# Collapse the notable sessions into per-kind counts. Blocking (awaiting)
# outranks transient (done) for both colour and background; when both are
# present the label shows awaiting first, then done. No notable sessions
# (idle/working-only agents) => hide the item entirely so the icon only appears
# when it needs attention (an awaiting-permission or freshly-completed agent).
label_color=$COLOR_MUTED
bg_color=$BG_NEUTRAL
label=
if [ "$awaiting_count" -gt 0 ]; then
  label_color=$COLOR_AWAITING
  bg_color=$BG_BLOCKING
  label="⏸ $awaiting_count awaiting"
  [ "$done_count" -gt 0 ] && label="$label  ✓ $done_count done"
elif [ "$done_count" -gt 0 ]; then
  label_color=$COLOR_DONE
  label="✓ $done_count done"
else
  hide_item
  exit 0
fi

sketchybar --set "$ITEM" \
  drawing=on \
  "icon.color=$icon_color" \
  "background.color=$bg_color" \
  label.drawing=on \
  "label=$label" \
  "label.color=$label_color" >/dev/null 2>&1

exit 0
