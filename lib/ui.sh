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

nimo_banner() {
    [ "${NIMO_QUIET:-0}" = "1" ] && return 0
    [ -t 1 ] && [ "${NIMO_NO_CLEAR:-0}" != "1" ] && clear
    printf '%s' "$NIMO_C_CYAN"
    cat <<'ART'

                 .───────────.
               .'             '.
              /    ·       ·    \
             |        ─          |
              \                 /
               '._           _.'
                  '─────────'

                       NIMO

              make your computer
                   feel better.

ART
    printf '%s' "$NIMO_C_RESET"
    printf '%s                      v%s%s\n\n' "$NIMO_C_DIM" "$NIMO_VERSION" "$NIMO_C_RESET"
}

nimo_title() { printf '\n  %s%s%s\n\n' "$NIMO_C_BOLD" "$1" "$NIMO_C_RESET"; }
nimo_say()   { printf '  %s\n' "$1"; }
nimo_dim()   { printf '  %s%s%s\n' "$NIMO_C_DIM" "$1" "$NIMO_C_RESET"; }
nimo_ok()    { printf '  %s✓%s %s\n' "$NIMO_C_GREEN" "$NIMO_C_RESET" "$1"; }
nimo_warn()  { printf '  %s!%s %s\n' "$NIMO_C_YELLOW" "$NIMO_C_RESET" "$1"; }
nimo_err()   { printf '  %s✗%s %s\n' "$NIMO_C_RED" "$NIMO_C_RESET" "$1" >&2; }
nimo_blank() { printf '\n'; }
nimo_rule()  { printf '  %s%s%s\n' "$NIMO_C_DIM" "────────────────────────────────────────────────────" "$NIMO_C_RESET"; }

# nimo_row <label> <size> [note]
nimo_row() {
    printf '  %-30s %12s  %s%s%s\n' "$1" "$2" "$NIMO_C_DIM" "${3:-}" "$NIMO_C_RESET"
}

nimo_total() {
    printf '  %s%-30s %12s%s\n' "$NIMO_C_BOLD" "$1" "$2" "$NIMO_C_RESET"
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
        printf '  %-13s %s  %s%s%s\n' "$1" "$2" "$NIMO_C_DIM" "$3" "$NIMO_C_RESET"
    else
        printf '  %-13s %s\n' "$1" "$2"
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
