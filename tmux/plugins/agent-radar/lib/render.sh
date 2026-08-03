#!/usr/bin/env bash

status_label() {
  local status=$1
  if [ "${NO_COLOR:-0}" = 1 ]; then
    case "$status" in
      awaiting) printf '⏸ awaiting' ;;
      working) printf '⚙ working' ;;
      done) printf '✓ done' ;;
      idle) printf '✓ idle' ;;
      *) printf '? unknown' ;;
    esac
    return
  fi

  case "$status" in
    awaiting) printf '\033[38;2;247;118;142m⏸ awaiting\033[0m' ;;
    working) printf '\033[38;2;224;175;104m⚙ working\033[0m' ;;
    done) printf '\033[38;2;63;185;80m✓ done\033[0m' ;;
    idle) printf '\033[38;2;158;206;106m✓ idle\033[0m' ;;
    *) printf '\033[38;2;86;95;137m? unknown\033[0m' ;;
  esac
}

pill_cell() {
  local rank=$1 pane_target=$2
  case "$rank" in
    1) printf '#[fg=%s,bold]%s ' "$COLOR_AWAITING" "$pane_target" ;;
    2) printf '#[fg=%s,bold]%s ' "$COLOR_WORKING" "$pane_target" ;;
    3) printf '#[fg=%s,bold]✓%s ' "$COLOR_DONE" "$pane_target" ;;
    4) printf '#[fg=%s,nobold]%s ' "$COLOR_IDLE" "$pane_target" ;;
    *) printf '#[fg=%s,nobold]%s ' "$COLOR_MUTED" "$pane_target" ;;
  esac
}

dot_color() {
  local priority=$1 is_current=$2
  case "$priority" in
    0) printf '%s' "$COLOR_AWAITING"; return ;;
    1) printf '%s' "$COLOR_DONE"; return ;;
  esac
  if [ "$is_current" = 1 ]; then printf '%s' "$COLOR_IDLE"; return; fi
  case "$priority" in
    2) printf '%s' "$COLOR_MUTED" ;;
    *) printf '%s' "$COLOR_DIM" ;;
  esac
}

format_display_row() {
  local status=$1 target=$2 title=$3 status_cell target_cell
  status_cell=$(printf '%-10s' "$status")
  target_cell=$(printf '%-26.26s' "$target")

  if [ "${NO_COLOR:-0}" != 1 ]; then
    case "$status" in
      awaiting) status_cell=$(printf '\033[38;2;247;118;142m%s\033[0m' "$status_cell") ;;
      working) status_cell=$(printf '\033[38;2;224;175;104m%s\033[0m' "$status_cell") ;;
      done) status_cell=$(printf '\033[38;2;63;185;80m%s\033[0m' "$status_cell") ;;
      idle) status_cell=$(printf '\033[38;2;158;206;106m%s\033[0m' "$status_cell") ;;
      *) status_cell=$(printf '\033[38;2;86;95;137m%s\033[0m' "$status_cell") ;;
    esac
    target_cell=$(printf '\033[38;2;122;162;247m%s\033[0m' "$target_cell")
  fi

  printf '%s  %s  %s' "$status_cell" "$target_cell" "$title"
}
