#!/usr/bin/env bash
# nimo :: lib/ui.sh — banner, colors, output helpers.

NIMO_C_RESET=""; NIMO_C_DIM=""; NIMO_C_BOLD=""
NIMO_C_GREEN=""; NIMO_C_YELLOW=""; NIMO_C_RED=""; NIMO_C_CYAN=""

nimo_supports_color() {
    [ "${NIMO_COLOR:-auto}" = "never" ] && return 1
    [ "${NIMO_COLOR:-auto}" = "always" ] && return 0
    [ -n "${NO_COLOR:-}" ] && return 1
    [ -t 1 ] || return 1
    case "${TERM:-}" in dumb|"") return 1 ;; esac
    return 0
}

nimo_init_colors() {
    if nimo_supports_color; then
        NIMO_C_RESET=$'\033[0m'
        NIMO_C_DIM=$'\033[2m'
        NIMO_C_BOLD=$'\033[1m'
        NIMO_C_GREEN=$'\033[32m'
        NIMO_C_YELLOW=$'\033[33m'
        NIMO_C_RED=$'\033[31m'
        NIMO_C_CYAN=$'\033[36m'
    else
        NIMO_C_RESET=""; NIMO_C_DIM=""; NIMO_C_BOLD=""
        NIMO_C_GREEN=""; NIMO_C_YELLOW=""; NIMO_C_RED=""; NIMO_C_CYAN=""
    fi
}

nimo_cols() {
    local c=""
    command -v tput >/dev/null 2>&1 && c=$(tput cols 2>/dev/null)
    case "${c:-}" in
        ''|*[!0-9]*) c=80 ;;
    esac
    printf '%s' "$c"
}

# The full wordmark. Shown by `min` and `min help`.
nimo_logo() {
    [ "${NIMO_QUIET:-0}" = "1" ] && return 0
    if [ "$(nimo_cols)" -lt 40 ]; then
        nimo_header
        return 0
    fi
    if [ -t 1 ] && [ "${NIMO_NO_CLEAR:-0}" != "1" ]; then
        clear
    fi
    printf '\n%s' "$NIMO_C_CYAN"
    cat <<'ART'
   ███╗   ██╗██╗███╗   ███╗ ██████╗
   ████╗  ██║██║████╗ ████║██╔═══██╗
   ██╔██╗ ██║██║██╔████╔██║██║   ██║
   ██║╚██╗██║██║██║╚██╔╝██║██║   ██║
   ██║ ╚████║██║██║ ╚═╝ ██║╚██████╔╝
   ╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝ ╚═════╝
ART
    printf '%s' "$NIMO_C_RESET"
    printf '\n   %smake your computer feel better%s\n' "$NIMO_C_DIM" "$NIMO_C_RESET"
    printf '   %sv%s%s\n' "$NIMO_C_DIM" "$NIMO_VERSION" "$NIMO_C_RESET"
}

# One quiet line. Shown by every other command, so the output
# you came for stays on screen.
nimo_header() {
    [ "${NIMO_QUIET:-0}" = "1" ] && return 0
    printf '\n  %s◍%s %snimo%s %sv%s%s\n' \
        "$NIMO_C_CYAN" "$NIMO_C_RESET" \
        "$NIMO_C_BOLD" "$NIMO_C_RESET" \
        "$NIMO_C_DIM" "$NIMO_VERSION" "$NIMO_C_RESET"
}

# ---- panels -------------------------------------------------------------
#
# No right hand border on purpose: block characters and box drawing are not
# one byte wide, so anything that pads to a closing │ drifts out of line the
# moment a bar or an accent shows up.

NIMO_PAD="  "
NIMO_PANEL_WIDTH=52

nimo_dashes() {
    awk -v n="${1:-0}" 'BEGIN { for (i = 0; i < n; i++) printf "─" }'
}

nimo_panel_open() {
    local title="${1:-}" fill
    fill=$((NIMO_PANEL_WIDTH - ${#title} - 4))
    [ "$fill" -lt 0 ] && fill=0
    printf '\n  %s╭─ %s%s %s%s%s\n\n' \
        "$NIMO_C_DIM" "$NIMO_C_RESET$NIMO_C_BOLD" "$title" \
        "$NIMO_C_RESET$NIMO_C_DIM" "$(nimo_dashes "$fill")" "$NIMO_C_RESET"
    NIMO_PAD="     "
}

nimo_panel_close() {
    printf '\n  %s╰%s%s\n' "$NIMO_C_DIM" "$(nimo_dashes "$NIMO_PANEL_WIDTH")" "$NIMO_C_RESET"
    NIMO_PAD="  "
}

# Big numbers should read as big numbers.
nimo_size_color() {
    if [ "${1:-0}" -ge 1048576 ]; then
        printf '%s' "$NIMO_C_YELLOW"
    elif [ "${1:-0}" -ge 102400 ]; then
        printf '%s' "$NIMO_C_RESET"
    else
        printf '%s' "$NIMO_C_DIM"
    fi
}

nimo_title() { printf '\n  %s%s%s\n\n' "$NIMO_C_BOLD" "$1" "$NIMO_C_RESET"; }
nimo_say()   { printf '%s%s\n' "$NIMO_PAD" "$1"; }
nimo_dim()   { printf '%s%s%s%s\n' "$NIMO_PAD" "$NIMO_C_DIM" "$1" "$NIMO_C_RESET"; }
nimo_ok()    { printf '%s%s✓%s %s\n' "$NIMO_PAD" "$NIMO_C_GREEN" "$NIMO_C_RESET" "$1"; }
nimo_warn()  { printf '%s%s!%s %s\n' "$NIMO_PAD" "$NIMO_C_YELLOW" "$NIMO_C_RESET" "$1"; }
nimo_err()   { printf '  %s✗%s %s\n' "$NIMO_C_RED" "$NIMO_C_RESET" "$1" >&2; }
nimo_blank() { printf '\n'; }
nimo_rule()  { printf '%s%s%s%s\n' "$NIMO_PAD" "$NIMO_C_DIM" "$(nimo_dashes 41)" "$NIMO_C_RESET"; }

# nimo_row <label> <size> [note]
nimo_row() {
    if [ -n "${3:-}" ]; then
        printf '%s%-27s %12s  %s%s%s\n' "$NIMO_PAD" "$1" "$2" "$NIMO_C_DIM" "$3" "$NIMO_C_RESET"
    else
        printf '%s%-27s %12s\n' "$NIMO_PAD" "$1" "$2"
    fi
}

# The same row, but the size colours itself by how big it is.
nimo_row_kb() {
    printf '%s%-27s %s%12s%s  %s%s%s\n' \
        "$NIMO_PAD" "$1" \
        "$(nimo_size_color "$2")" "$(nimo_human_kb "$2")" "$NIMO_C_RESET" \
        "$NIMO_C_DIM" "${3:-}" "$NIMO_C_RESET"
}

nimo_total() {
    printf '%s%s%-27s %12s%s\n' "$NIMO_PAD" "$NIMO_C_BOLD" "$1" "$2" "$NIMO_C_RESET"
}

# transient progress line (tty only)
nimo_progress() {
    [ -t 1 ] || return 0
    [ "${NIMO_QUIET:-0}" = "1" ] && return 0
    printf '\r  %s%-52s%s' "$NIMO_C_DIM" "$1" "$NIMO_C_RESET"
}

nimo_progress_done() {
    [ -t 1 ] || return 0
    [ "${NIMO_QUIET:-0}" = "1" ] && return 0
    printf '\r%-60s\r' " "
}

# nimo_bar <value> <max> [width] — a plain proportional bar
nimo_bar() {
    awk -v v="${1:-0}" -v m="${2:-0}" -v w="${3:-14}" 'BEGIN {
        if (m <= 0) { for (i = 0; i < w; i++) printf "·"; exit }
        f = int((v / m) * w + 0.5)
        if (f < 1 && v > 0) f = 1
        if (f > w) f = w
        for (i = 0; i < f; i++) printf "█"
        for (i = f; i < w; i++) printf "·"
    }'
}

# nimo_meter <value> <max> [width] — the same bar, coloured
nimo_meter() {
    printf '%s%s%s' "$NIMO_C_CYAN" "$(nimo_bar "$1" "$2" "${3:-14}")" "$NIMO_C_RESET"
}

# nimo_fact <label> <value> [extra]
nimo_fact() {
    if [ -n "${3:-}" ]; then
        printf '%s%s%-12s%s %s  %s%s%s\n' "$NIMO_PAD" \
            "$NIMO_C_DIM" "$1" "$NIMO_C_RESET" "$2" "$NIMO_C_DIM" "$3" "$NIMO_C_RESET"
    else
        printf '%s%s%-12s%s %s\n' "$NIMO_PAD" "$NIMO_C_DIM" "$1" "$NIMO_C_RESET" "$2"
    fi
}

# nimo_plural <count> <word> -> "1 item" / "4 items"
nimo_plural() {
    if [ "${1:-0}" = "1" ]; then
        printf '1 %s' "$2"
    else
        printf '%s %ss' "${1:-0}" "$2"
    fi
}
