#!/usr/bin/env bash
# nimo :: lib/core.sh — platform helpers, sizes, safety guards.

nimo_is_macos() { [ "$(uname -s)" = "Darwin" ]; }

# Where nimo keeps everything it needs to undo itself.
NIMO_UNDO_DIR="$HOME/.nimo/undo"
NIMO_BACKUP_DIR="$HOME/.nimo/backups"

# human_kb <kilobytes> -> "1.2 GB"
nimo_human_kb() {
    awk -v k="${1:-0}" 'BEGIN{
        if (k <= 0) { printf "0 B"; exit }
        b = k * 1024
        split("B KB MB GB TB", u, " ")
        i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        if (i <= 2)      printf "%d %s", b, u[i]
        else if (b >= 100) printf "%.0f %s", b, u[i]
        else             printf "%.1f %s", b, u[i]
    }'
}

# size of a path in KB (0 if missing/unreadable)
nimo_path_kb() {
    [ -e "$1" ] || { echo 0; return 0; }
    du -sk "$1" 2>/dev/null | awk 'NR==1{print $1+0; found=1} END{if(!found) print 0}'
}

# number of entries directly inside a directory
nimo_count_children() {
    [ -d "$1" ] || { echo 0; return 0; }
    find "$1" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '
}

# Refuse to touch anything that is not clearly disposable.
nimo_is_protected() {
    local p="${1:-}"
    [ -z "$p" ] && return 0
    case "$p" in
        */../*|*/..) return 0 ;;
    esac
    case "$p" in
        / | /Users | /Users/ | /home | /home/ | /System* | /Library | /Applications | /bin* | /usr | /usr/* | /etc* | /var | /private | /opt)
            return 0 ;;
    esac
    [ "$p" = "$HOME" ] && return 0
    [ "$p" = "$HOME/" ] && return 0
    # must live under $HOME — nimo never touches system-owned paths
    case "$p" in
        "$HOME"/*) return 1 ;;
        *) return 0 ;;
    esac
}

# nimo_confirm <question>  -> 0 = yes
nimo_confirm() {
    [ "${NIMO_ASSUME_YES:-0}" = "1" ] && return 0
    if [ ! -t 0 ]; then
        nimo_warn "not a terminal — refusing to continue without confirmation (use --yes)"
        return 1
    fi
    local answer=""
    printf '  %s [y/N] ' "$1"
    read -r answer || return 1
    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

# delete every child of a directory, keeping the directory itself
nimo_purge_children() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    if nimo_is_protected "$dir"; then
        nimo_err "refusing to clean protected path: $dir"
        return 1
    fi
    find "$dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null \
        | xargs -0 rm -rf 2>/dev/null
    return 0
}

# delete a whole path
nimo_purge_path() {
    local p="$1"
    [ -e "$p" ] || return 0
    if nimo_is_protected "$p"; then
        nimo_err "refusing to remove protected path: $p"
        return 1
    fi
    rm -rf "$p" 2>/dev/null
    return 0
}

nimo_have() { command -v "$1" >/dev/null 2>&1; }

# --- disk ----------------------------------------------------------------

# These must always print a number. On a home directory df cannot stat — a
# stale mount, a deleted directory — it printed nothing at all, and every
# arithmetic test downstream then failed with "integer expression expected".
nimo_disk_free_kb() {
    df -Pk "$HOME" 2>/dev/null \
        | awk 'NR == 2 {print $4 + 0; found = 1} END {if (!found) print 0}'
}

nimo_disk_total_kb() {
    df -Pk "$HOME" 2>/dev/null \
        | awk 'NR == 2 {print $2 + 0; found = 1} END {if (!found) print 0}'
}

nimo_disk_line() {
    local free total
    free=$(nimo_disk_free_kb)
    total=$(nimo_disk_total_kb)
    [ "${total:-0}" -gt 0 ] || return 0
    printf '%s%sDisk         %s free of %s%s\n' "$NIMO_PAD" \
        "$NIMO_C_DIM" "$(nimo_human_kb "$free")" "$(nimo_human_kb "$total")" "$NIMO_C_RESET"
}

# kilobytes -> bytes, for --json
nimo_kb_to_bytes() { awk -v k="${1:-0}" 'BEGIN {printf "%.0f", k * 1024}'; }

nimo_count_dir_items() {
    [ -d "$1" ] || { printf '0'; return 0; }
    find "$1" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '
}

# How many non-empty lines are in this string?
#
# `grep -c .` prints 0 and exits 1 on empty input, so the obvious
# `$(... || printf 0)` quietly produces "0\n0" and every later test on it
# blows up. This is that bug, fixed once.
nimo_line_count() {
    [ -n "${1:-}" ] || { printf '0'; return 0; }
    printf '%s\n' "$1" | grep -c . 2>/dev/null || true
}

# --- ~/.nimo/config ------------------------------------------------------
#
# A handful of `key = value` lines. It is read, not sourced: nothing in this
# file can run as code, whatever ends up in it.
#
#   days  = 60
#   limit = 25
#   jobs  = 8
#   color = never
#   tidy  = Desktop Tidy

nimo_read_config() {
    local file="$HOME/.nimo/config" line key value
    [ -r "$file" ] || return 0

    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        key=$(printf '%s' "$line" | sed -e 's/=.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//')
        value=$(printf '%s' "$line" | sed -e 's/^[^=]*=//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -n "$value" ] || continue
        case "$key" in
            days)  case "$value" in ''|*[!0-9]*) ;; *) NIMO_DAYS="$value" ;; esac ;;
            limit) case "$value" in ''|*[!0-9]*) ;; *) NIMO_LIMIT="$value" ;; esac ;;
            jobs)  case "$value" in ''|*[!0-9]*) ;; *) NIMO_JOBS="$value" ;; esac ;;
            color) case "$value" in auto|always|never) NIMO_COLOR="$value" ;; esac ;;
            tidy)  NIMO_TIDY_DIR_NAME="$value" ;;
        esac
    done < "$file"
    return 0
}

# A path that is not already taken.
#
# Undo records are named by the second they were made in, and two runs inside
# one second would otherwise land on the same name — where the second would
# truncate the first, quietly throwing away the only record of how to undo it.
nimo_free_file() {
    local base="$1" ext="$2" n=2 try
    try="${base}${ext}"
    # The suffix is _2, not -2, on purpose: these names are read back with a
    # glob and the newest is taken from the end, so the extra copy has to sort
    # *after* the plain name. "-" sorts before "." and would come out first;
    # "_" sorts after it and comes out last, which is what newest means here.
    while [ -e "$try" ] && [ "$n" -lt 100 ]; do
        try="${base}_${n}${ext}"
        n=$((n + 1))
    done
    printf '%s' "$try"
}
