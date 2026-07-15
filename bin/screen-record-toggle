#!/bin/bash
# Toggle a macOS screen recording driven by `screencapture -v`.
# First invocation: starts recording to a temp file.
# Second invocation: stops, prompts for a name, re-encodes with x264 CRF 17
# at native resolution, and saves to ~/Documents/screen-recordings/.
#
# screencapture reads stdin to detect a stop keystroke. If stdin is /dev/null
# it gets immediate EOF and quits. We feed it a FIFO held open by a sleep
# process so it stays running until we explicitly SIGINT it.

set -uo pipefail

OUT_DIR="$HOME/Documents/screen-recordings"
STATE="/tmp/aerospace-screencap.state"
FIFO="/tmp/aerospace-screencap.fifo"
LOGFILE="/tmp/aerospace-screencap.log"
mkdir -p "$OUT_DIR"

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"Screen Recording\"" >/dev/null 2>&1 || true
}

log() {
  /bin/date "+%F %T $*" >>"$LOGFILE"
}

read_state() {
  SC_PID=""; SLEEP_PID=""; RAW=""
  [[ -f "$STATE" ]] || return 1
  { read -r SC_PID; read -r SLEEP_PID; read -r RAW; } < "$STATE"
  [[ -n "$SC_PID" ]] && /bin/kill -0 "$SC_PID" 2>/dev/null
}

if read_state; then
  # ---- STOP ----
  log "stop: sc=$SC_PID sleep=$SLEEP_PID raw=$RAW"

  /bin/kill -INT "$SC_PID" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    /bin/kill -0 "$SC_PID" 2>/dev/null || break
    /bin/sleep 0.3
  done
  [[ -n "$SLEEP_PID" ]] && /bin/kill "$SLEEP_PID" 2>/dev/null || true
  rm -f "$STATE" "$FIFO"

  if [[ -z "$RAW" || ! -f "$RAW" ]]; then
    log "stop: raw missing ($RAW)"
    notify "Could not locate raw recording file"
    exit 1
  fi

  NAME=$(/usr/bin/osascript <<'OSA' 2>/dev/null || true
try
  tell application "System Events"
    activate
    set theResponse to display dialog "Save recording as:" default answer "" with title "Compress Recording" buttons {"Cancel", "Save"} default button "Save"
    return text returned of theResponse
  end tell
on error
  return ""
end try
OSA
)
  NAME=$(printf '%s' "$NAME" | /usr/bin/sed 's/^ *//; s/ *$//')

  if [[ -z "$NAME" ]]; then
    log "stop: cancelled, raw=$RAW"
    notify "Cancelled — raw kept at $RAW"
    exit 0
  fi

  NAME="${NAME%.mov}"
  OUT="$OUT_DIR/${NAME}.mov"

  HAS_AUDIO=$(/opt/homebrew/bin/ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$RAW" 2>/dev/null | head -1 || true)

  notify "Compressing…"
  log "compress: $RAW -> $OUT (audio=${HAS_AUDIO:-none})"
  if [[ -n "$HAS_AUDIO" ]]; then
    /opt/homebrew/bin/ffmpeg -y -i "$RAW" \
      -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -movflags +faststart \
      -c:a aac -b:a 192k "$OUT" >>"$LOGFILE" 2>&1
  else
    /opt/homebrew/bin/ffmpeg -y -i "$RAW" \
      -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -movflags +faststart \
      "$OUT" >>"$LOGFILE" 2>&1
  fi
  rc=$?

  if [[ $rc -eq 0 && -f "$OUT" ]]; then
    rm -f "$RAW"
    log "compress: ok"
    notify "Saved ${NAME}.mov"
  else
    log "compress: ffmpeg rc=$rc"
    notify "ffmpeg failed — see $LOGFILE; raw at $RAW"
  fi
else
  # ---- START ----
  # Clean any leftovers from a crashed prior run
  [[ -e "$FIFO" ]] && rm -f "$FIFO"
  rm -f "$STATE"

  RAW="/tmp/aerospace-rec-$(/bin/date +%Y%m%d-%H%M%S).mov"
  /usr/bin/mkfifo "$FIFO"

  # sleep holds the write end of the FIFO open so screencapture's stdin never
  # gets EOF. When we kill the sleep at stop time, the FIFO closes cleanly.
  /bin/sleep 86400 > "$FIFO" &
  SLEEP_PID=$!
  disown

  /usr/bin/nohup /usr/sbin/screencapture -v "$RAW" >>"$LOGFILE" 2>&1 < "$FIFO" &
  SC_PID=$!
  disown

  printf '%s\n%s\n%s\n' "$SC_PID" "$SLEEP_PID" "$RAW" > "$STATE"

  /bin/sleep 0.6
  if /bin/kill -0 "$SC_PID" 2>/dev/null; then
    log "start: sc=$SC_PID sleep=$SLEEP_PID raw=$RAW"
    notify "Recording — press ⌃⌘O then R to stop"
  else
    log "start: screencapture exited immediately"
    /bin/kill "$SLEEP_PID" 2>/dev/null || true
    rm -f "$FIFO" "$STATE"
    notify "screencapture failed to start (see $LOGFILE)"
  fi
fi
