#!/usr/bin/env bash

state_status() {
  local state_file=$1 pane_id=$2
  [ -f "$state_file" ] && [ ! -L "$state_file" ] || return 1
  jq -er --arg pane "$pane_id" --argjson now "$NOW" '
    select(.pane_id == $pane)
    | select(.status == "idle" or .status == "working" or .status == "awaiting")
    | select((.updated_epoch | type) == "number")
    | select(.updated_epoch <= ($now + 300))
    | [
        .status,
        .updated_epoch,
        (.flash.kind // ""),
        (.flash.until_epoch // 0),
        (.flash.id // ((.flash.until_epoch // 0) | tostring))
      ] | @tsv
  ' "$state_file" 2>/dev/null
}

filter_agent_panes() {
  local panes_file=$1 process_file=$2 destination=$3
  awk '
    NR == FNR {
      field_count = split($0, fields, "\t")
      if (field_count >= 6) {
        pane_count++
        pane_line[pane_count] = $0
        pane_for_pid[fields[5]] = pane_count
      }
      next
    }
    {
      pid = $1
      parent[pid] = $2
      command[pid] = $3
    }
    END {
      for (pid in command) {
        count = split(command[pid], parts, "/")
        if (parts[count] != agent_process) {
          continue
        }
        current = pid
        for (depth = 0; current != "" && current != "0" && depth < 256; depth++) {
          if (current in pane_for_pid) {
            matched[pane_for_pid[current]] = 1
            break
          }
          current = parent[current]
        }
      }
      for (i = 1; i <= pane_count; i++) {
        if (i in matched) {
          print pane_line[i]
        }
      }
    }
  ' agent_process="$AGENT_RADAR_PROCESS_BASENAME" "$panes_file" "$process_file" >"$destination"
}

clean_field() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

clean_title() {
  local title
  title=$(clean_field "$1")
  agent_clean_title "$title"
}

write_process_snapshot() {
  local destination=$1
  if [ -n "${TMUX_AGENT_ENGINE_PS_FILE:-}" ]; then
    cp "$TMUX_AGENT_ENGINE_PS_FILE" "$destination"
  else
    ps -axo pid=,ppid=,comm= >"$destination"
  fi
}

list_rows() {
  require_command jq
  local mode=${1:-full}
  local temp_dir process_file panes_file agent_panes_file live_panes_file rows_file
  temp_dir=$(mktemp -d)
  process_file=$temp_dir/processes
  panes_file=$temp_dir/panes
  agent_panes_file=$temp_dir/agent-panes
  live_panes_file=$temp_dir/live-panes
  rows_file=$temp_dir/rows
  trap "rm -rf -- '$temp_dir'" EXIT

  write_process_snapshot "$process_file"
  "$TMUX_BIN" list-panes -a \
    -F '#{pane_id}	#{session_name}	#{window_index}	#{pane_index}	#{pane_pid}	#{pane_title}' \
    >"$panes_file" 2>/dev/null || return 0
  filter_agent_panes "$panes_file" "$process_file" "$agent_panes_file"

  : >"$live_panes_file"
  : >"$rows_file"

  local pane_id session window pane_index pane_pid title target state_file
  local state_data hook_status status rank label display
  local flash_kind flash_until flash_token ack_file ack_token
  while IFS=$'\t' read -r pane_id session window pane_index pane_pid title; do
    case "$pane_id" in
      %|%*[!0-9]*|[!%]*|'') continue ;;
    esac
    case "$pane_pid" in
      *[!0-9]*|'') continue ;;
    esac
    printf '%s\n' "$pane_id" >>"$live_panes_file"

    state_file=$STATE_DIR/${pane_id#%}.json
    status=unknown
    hook_status=; flash_kind=; flash_until=0

    if state_data=$(state_status "$state_file" "$pane_id"); then
      IFS=$'\t' read -r hook_status _ flash_kind flash_until flash_token <<<"$state_data"
    fi

    status=${hook_status:-unknown}
    if [ "$status" = idle ] && [ "$flash_kind" = done ]; then
      ack_file=$STATE_DIR/.ack/${pane_id#%}
      ack_token=
      if [ -f "$ack_file" ] && [ ! -L "$ack_file" ]; then
        IFS= read -r ack_token <"$ack_file" || ack_token=
      fi
      # Tmux surfaces retain the last completed state until the next lifecycle
      # event. External notification consumers keep the configured TTL.
      if [ "$ack_token" != "$flash_token" ] &&
         { [ "$mode" != notify ] || [ "${flash_until:-0}" -gt "$NOW" ]; }; then
        status=done
      fi
    fi

    case "$status" in
      awaiting) rank=1 ;;
      working) rank=2 ;;
      done) rank=3 ;;
      idle) rank=4 ;;
      *) rank=5 ;;
    esac
    session=$(clean_field "$session")
    target=$session:$window.$pane_index
    if [ "$mode" = lean ] || [ "$mode" = notify ]; then
      printf '%s\t%s\t%s\t%s\n' "$rank" "$pane_id" "$session" "$target" >>"$rows_file"
    else
      label=$(status_label "$status")
      title=$(clean_title "$title")
      display=$(format_display_row "$status" "$target" "$title")
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$rank" "$pane_id" "$session" "$target" "$label" "$title" "$display" >>"$rows_file"
    fi
  done <"$agent_panes_file"

  if [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ]; then
    local candidate candidate_pane
    for candidate in "$STATE_DIR"/*.json; do
      [ -e "$candidate" ] || break
      candidate_pane=%$(basename "$candidate" .json)
      if ! grep -Fxq "$candidate_pane" "$live_panes_file"; then
        rm -f "$candidate" "$STATE_DIR/.ack/${candidate_pane#%}"
      fi
    done
  fi

  sort -t $'\t' -k1,1n -k3,3 -k4,4 "$rows_file"
}
