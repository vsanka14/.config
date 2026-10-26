#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^-?[0-9]+$ || "$1" -eq 0 ]]; then
    echo "usage: adjust-gaps <non-zero pixel delta>" >&2
    exit 64
fi

delta="$1"
config_path="${AEROSPACE_CONFIG_PATH:-$HOME/.config/aerospace/aerospace.toml}"
lock_dir="${TMPDIR:-/tmp}/aerospace-adjust-gaps-${UID}.lock"
lock_held=false
temp_path=""
backup_path=""

cleanup() {
    [[ -n "$temp_path" && -e "$temp_path" ]] && /bin/rm -f "$temp_path"
    [[ -n "$backup_path" && -e "$backup_path" ]] && /bin/rm -f "$backup_path"
    if [[ "$lock_held" == true ]]; then
        /bin/rm -f "$lock_dir/pid"
        /bin/rmdir "$lock_dir" 2>/dev/null || true
    fi
}
trap cleanup EXIT

for ((attempt = 0; attempt < 250; attempt++)); do
    if /bin/mkdir "$lock_dir" 2>/dev/null; then
        printf '%s\n' "$$" >"$lock_dir/pid"
        lock_held=true
        break
    fi

    if [[ -f "$lock_dir/pid" ]]; then
        lock_pid="$(<"$lock_dir/pid")"
        if [[ "$lock_pid" =~ ^[0-9]+$ ]] && ! /bin/kill -0 "$lock_pid" 2>/dev/null; then
            /bin/rm -f "$lock_dir/pid"
            /bin/rmdir "$lock_dir" 2>/dev/null || true
        fi
    fi
    /bin/sleep 0.02
done

if [[ "$lock_held" != true ]]; then
    echo "adjust-gaps: timed out waiting for another adjustment" >&2
    exit 75
fi

if [[ ! -f "$config_path" ]]; then
    echo "adjust-gaps: config not found: $config_path" >&2
    exit 66
fi

temp_path="$(/usr/bin/mktemp "${config_path}.new.XXXXXX")"
backup_path="$(/usr/bin/mktemp "${config_path}.backup.XXXXXX")"
/bin/cp -p "$config_path" "$backup_path"

if ! GAP_DELTA="$delta" /usr/bin/perl -ne '
    BEGIN {
        $delta = 0 + $ENV{"GAP_DELTA"};
        $in_gaps = 0;
        $changed = 0;
    }

    if (/^\s*\[gaps\]\s*(?:#.*)?$/) {
        $in_gaps = 1;
    } elsif (/^\s*\[/) {
        $in_gaps = 0;
    }

    if ($in_gaps && /^\s*outer\.(?:left|right|top|bottom)\s*=/) {
        $changed += s!(=\s*|},\s*)(\d+)!do {
            my $value = $2 + $delta;
            $1 . ($value < 0 ? 0 : $value);
        }!ge;
    }

    print;

    END {
        if ($changed == 0) {
            print STDERR "adjust-gaps: no outer gap values found\n";
            exit 65;
        }
    }
' "$config_path" >"$temp_path"; then
    exit 65
fi

/bin/chmod "$(/usr/bin/stat -f '%Lp' "$config_path")" "$temp_path"
/bin/mv "$temp_path" "$config_path"
temp_path=""

if ! aerospace reload-config --no-gui; then
    /bin/mv "$backup_path" "$config_path"
    backup_path=""
    aerospace reload-config --no-gui >/dev/null 2>&1 || true
    echo "adjust-gaps: reload failed; restored the previous config" >&2
    exit 1
fi

/bin/rm -f "$backup_path"
backup_path=""
