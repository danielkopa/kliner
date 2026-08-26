#!/usr/bin/env bash
# nimo :: lib/core.sh — platform helpers, sizes, safety guards.

nimo_is_macos() { [ "$(uname -s)" = "Darwin" ]; }

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

nimo_disk_free_kb()  { df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 {print $4 + 0}'; }
nimo_disk_total_kb() { df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 {print $2 + 0}'; }

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
