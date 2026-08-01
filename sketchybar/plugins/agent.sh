#!/bin/bash

# Single owner of the `agent` menu-bar item. Renders Copilot agent status inline
# as a label next to the agent icon (no popup):
#   - a completion ("done") shows a transient green label that clears itself when
#     the underlying flash expires (~DONE_FLASH_TTL in bin/tmux-agent-status);
#   - an awaiting-permission agent shows a blocking red label (with a red-tinted
#     item background) that persists until the agent moves on.
# The item is hidden entirely unless there is a notable agent (awaiting or done);
# idle/working-only agents draw nothing, so the icon only appears when it needs
# attention.
# The `bin/tmux-agent-status` hook raises `sketchybar --trigger agent_notify` on
# every real transition, and the notable set + colour are re-derived from
# `bin/tmux-agent-engine --notify-lines`, so this plugin never duplicates the
# pane-scan logic and stays in lockstep with the tmux status-right.
#
# Bash 3.2 (macOS) safe: indexed arrays only, no associative arrays / mapfile.

ITEM=${NAME:-agent}
ENGINE=${AGENT_ENGINE_BIN:-$HOME/.config/bin/tmux-agent-engine}
MAX_ENTRIES=3

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

out=$("$ENGINE" --notify-lines 2>/dev/null)
if [ -z "$out" ]; then
  hide_item
  exit 0
fi

color=
awaiting_entries=()
done_entries=()
while IFS=$'\t' read -r tag field_a field_b; do
  case "$tag" in
    COLOR) color=$field_a ;;
    LINE)
      case "$field_b" in
        awaiting) awaiting_entries+=("⏸ $field_a") ;;
        done) done_entries+=("✓ $field_a") ;;
      esac
      ;;
  esac
done <<EOF
$out
EOF

icon_color=$(hex_to_color "${color:-#7dcfff}")

# Blocking (awaiting) outranks transient (done) for both colour and background.
awaiting_count=${#awaiting_entries[@]}
done_count=${#done_entries[@]}

label_color=$COLOR_MUTED
bg_color=$BG_NEUTRAL
entries=()
if [ "$awaiting_count" -gt 0 ]; then
  label_color=$COLOR_AWAITING
  bg_color=$BG_BLOCKING
  entries=("${awaiting_entries[@]}" "${done_entries[@]}")
elif [ "$done_count" -gt 0 ]; then
  label_color=$COLOR_DONE
  entries=("${done_entries[@]}")
fi

# Compose a compact label from the notable entries, capped with a "+N" tail so
# the bar never overflows. No notable entries (idle/working-only agents) => hide
# the item entirely so the icon only appears when it needs attention (an
# awaiting-permission or freshly-completed agent).
total=${#entries[@]}
if [ "$total" -eq 0 ]; then
  hide_item
  exit 0
fi

label=
shown=$total
extra=0
if [ "$total" -gt "$MAX_ENTRIES" ]; then
  shown=$MAX_ENTRIES
  extra=$((total - shown))
fi
i=0
while [ "$i" -lt "$shown" ]; do
  if [ -n "$label" ]; then label="$label  "; fi
  label="$label${entries[$i]}"
  i=$((i + 1))
done
[ "$extra" -gt 0 ] && label="$label  +$extra"

sketchybar --set "$ITEM" \
  drawing=on \
  "icon.color=$icon_color" \
  "background.color=$bg_color" \
  label.drawing=on \
  "label=$label" \
  "label.color=$label_color" >/dev/null 2>&1

exit 0
