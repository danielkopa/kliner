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
    printf '\n   %smake your workspace clean%s\n' "$NIMO_C_DIM" "$NIMO_C_RESET"
    printf '   %sv%s%s\n' "$NIMO_C_DIM" "$NIMO_VERSION" "$NIMO_C_RESET"
}

# nimo itself. The face from the very first sketch, kept.
# nimo itself.
#
# The rows are kept in one place because two things draw them: the plain
# version, and the one that draws itself in and blinks. The eyes are their own
# row so the blink can redraw exactly that line and nothing else.
NIMO_FACE_EYES_OPEN="           │     ●         ●     │"
NIMO_FACE_EYES_SHUT="           │     ─         ─     │"

nimo_face_rows() {
    cat <<'FACE'
              ╭───────────────╮
            ╭─╯               ╰─╮
           ╭╯                   ╰╮
FACE
    printf '%s\n' "$NIMO_FACE_EYES_OPEN"
    cat <<'FACE'
           │                     │
           │      ╰───────╯      │
           ╰╮                   ╭╯
            ╰─╮               ╭─╯
              ╰───────────────╯
FACE
}

nimo_face() {
    printf '\n%s' "$NIMO_C_CYAN"
    nimo_face_rows
    printf '%s' "$NIMO_C_RESET"
}

# Can we afford to animate? Only with a terminal to draw on, a shell that can
# sleep in fractions, and nobody having asked for quiet.
nimo_can_animate() {
    [ "${NIMO_ANIMATE:-auto}" = "never" ] && return 1
    # The suite has no terminal, so the animated path could never be checked —
    # which is how a cursor escape that put the whole prompt on top of the face
    # shipped. This is the only way in.
    [ "${NIMO_ANIMATE_FORCE:-0}" = "1" ] && return 0
    [ "${NIMO_QUIET:-0}" = "1" ] && return 1
    [ -t 1 ] || return 1
    case "${TERM:-}" in dumb|"") return 1 ;; esac
    sleep 0.01 2>/dev/null || return 1
    return 0
}

# The face, drawn a row at a time, and then one blink.
#
# Four hundred milliseconds in total. Long enough to be a greeting, short
# enough that nobody waiting on `min doctor` ever notices it.
nimo_face_hello() {
    if ! nimo_can_animate; then
        nimo_face
        return 0
    fi

    printf '\n%s' "$NIMO_C_CYAN"

    local row
    while IFS= read -r row; do
        printf '%s\n' "$row"
        sleep 0.025
    done <<EOF
$(nimo_face_rows)
EOF

    # The eyes are six rows above where the cursor now sits.
    #
    # Up and down, never save and restore. `\033[s` and `\033[u` are not the
    # same escape on every terminal — some read `CSI s` as a margin command
    # and never move the cursor back. On those, nimo left the cursor six rows
    # up and then printed its prompt, its hint and its whole menu straight
    # over its own face. `\033[6A` / `\033[6B` are relative, and universal.
    sleep 0.12
    printf '\033[6A\r%s\033[6B\r' "$NIMO_FACE_EYES_SHUT"
    sleep 0.11
    printf '\033[6A\r%s\033[6B\r' "$NIMO_FACE_EYES_OPEN"

    printf '%s' "$NIMO_C_RESET"
    return 0
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

# How wide nimo draws.
#
# 52 was a constant, which is fine on a full-width terminal and wrong on every
# other one — and half-width is exactly where this tool gets used, next to the
# desktop it is tidying. A panel wider than the window wraps every rule and
# every row, and a wrapped box reads as a broken one.
#
# Three numbers come out of it: the panel, the label column inside a row, and
# the rule under the rows. They move together, so a narrow window loses label
# room rather than alignment.
NIMO_PANEL_WIDTH=52
NIMO_LABEL_WIDTH=27
NIMO_RULE_WIDTH=41
NIMO_BAR_WIDTH=16
NIMO_MENU_BAR_WIDTH=12
NIMO_TOP_NAME_WIDTH=22
NIMO_COLS=80

# Not nimo_measure: lib/scan.sh already has one of those, it is sourced later,
# and the second definition quietly wins. Two functions with the same name in
# one program is a bug waiting for the day somebody calls the wrong one.
nimo_measure_width() {
    local cols="${COLUMNS:-}"
    [ -n "$cols" ] || cols=$(tput cols 2>/dev/null) || cols=""
    case "${cols:-}" in
        ''|*[!0-9]*) cols=80 ;;
    esac

    NIMO_COLS="$cols"
    NIMO_PANEL_WIDTH=$((cols - 6))
    [ "$NIMO_PANEL_WIDTH" -gt 52 ] && NIMO_PANEL_WIDTH=52
    [ "$NIMO_PANEL_WIDTH" -lt 26 ] && NIMO_PANEL_WIDTH=26

    # the size column is 12 wide with two spaces either side; the label gets
    # what is left, and never less than a name can live in
    NIMO_LABEL_WIDTH=$((NIMO_PANEL_WIDTH - 25))
    [ "$NIMO_LABEL_WIDTH" -lt 10 ] && NIMO_LABEL_WIDTH=10

    NIMO_RULE_WIDTH=$((NIMO_PANEL_WIDTH - 11))
    [ "$NIMO_RULE_WIDTH" -lt 12 ] && NIMO_RULE_WIDTH=12

    # the bars go last, because they are the part a narrow window can lose
    # without losing anything you needed to read
    NIMO_BAR_WIDTH=$((NIMO_PANEL_WIDTH - 36))
    [ "$NIMO_BAR_WIDTH" -gt 16 ] && NIMO_BAR_WIDTH=16
    [ "$NIMO_BAR_WIDTH" -lt 6 ] && NIMO_BAR_WIDTH=6
    NIMO_MENU_BAR_WIDTH=$((NIMO_PANEL_WIDTH - 40))
    [ "$NIMO_MENU_BAR_WIDTH" -gt 12 ] && NIMO_MENU_BAR_WIDTH=12
    [ "$NIMO_MENU_BAR_WIDTH" -lt 4 ] && NIMO_MENU_BAR_WIDTH=4

    # min top has a name, a size and a bar and no note, so it can give the
    # name more room than a table row gets
    NIMO_TOP_NAME_WIDTH=$((NIMO_PANEL_WIDTH - NIMO_BAR_WIDTH - 14))
    [ "$NIMO_TOP_NAME_WIDTH" -gt 22 ] && NIMO_TOP_NAME_WIDTH=22
    [ "$NIMO_TOP_NAME_WIDTH" -lt 10 ] && NIMO_TOP_NAME_WIDTH=10
}

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
nimo_rule()  { printf '%s%s%s%s\n' "$NIMO_PAD" "$NIMO_C_DIM" "$(nimo_dashes "$NIMO_RULE_WIDTH")" "$NIMO_C_RESET"; }

# Is there room for the note on the end of a row?
#
# A row is a label, a size and a note, and only the first two are the data.
# In a narrow window the note is what goes: a wrapped note turns a column of
# numbers into a paragraph, and the numbers were the point. Prose lines are
# left to wrap — prose reads fine wrapped, a table does not.
# The whole row is pad + label + size + note, so the question is how wide the
# *window* is, not how wide the panel is: a 52-column panel still writes a
# 68-column line once a note is on the end of it.
nimo_room_for_note() { [ "$NIMO_COLS" -ge 72 ]; }

# nimo_row <label> <size> [note]
nimo_row() {
    if [ -n "${3:-}" ] && nimo_room_for_note; then
        printf "%s%-${NIMO_LABEL_WIDTH}s %12s  %s%s%s\n" "$NIMO_PAD" "$1" "$2" "$NIMO_C_DIM" "$3" "$NIMO_C_RESET"
    else
        printf "%s%-${NIMO_LABEL_WIDTH}s %12s\n" "$NIMO_PAD" "$1" "$2"
    fi
}

# The same row, but the size colours itself by how big it is.
nimo_row_kb() {
    local note="${3:-}"
    nimo_room_for_note || note=""
    if [ -n "$note" ]; then
        printf "%s%-${NIMO_LABEL_WIDTH}s %s%12s%s  %s%s%s\n" \
            "$NIMO_PAD" "$1" \
            "$(nimo_size_color "$2")" "$(nimo_human_kb "$2")" "$NIMO_C_RESET" \
            "$NIMO_C_DIM" "$note" "$NIMO_C_RESET"
    else
        printf "%s%-${NIMO_LABEL_WIDTH}s %s%12s%s\n" \
            "$NIMO_PAD" "$1" \
            "$(nimo_size_color "$2")" "$(nimo_human_kb "$2")" "$NIMO_C_RESET"
    fi
}

nimo_total() {
    printf "%s%s%-${NIMO_LABEL_WIDTH}s %12s%s\n" "$NIMO_PAD" "$NIMO_C_BOLD" "$1" "$2" "$NIMO_C_RESET"
}

# transient progress line (tty only)
nimo_progress() {
    [ -t 1 ] || return 0
    [ "${NIMO_QUIET:-0}" = "1" ] && return 0
    printf "\r  %s%-${NIMO_PANEL_WIDTH}s%s" "$NIMO_C_DIM" "$1" "$NIMO_C_RESET"
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
# Two spaces after the name, not one.
#
# The window tells a fact's name from its value by splitting on two or more
# spaces, and %-12s only guarantees that while the name is short enough to be
# padded. "Downloads older" is fifteen characters: it came out with a single
# space, so the window read the whole line as a name with no value and the
# fact silently never arrived. One space was the difference between a fact
# nimo prints and a fact anything can use.
nimo_fact() {
    if [ -n "${3:-}" ] && nimo_room_for_note; then
        printf '%s%s%-12s%s  %s  %s%s%s\n' "$NIMO_PAD" \
            "$NIMO_C_DIM" "$1" "$NIMO_C_RESET" "$2" "$NIMO_C_DIM" "$3" "$NIMO_C_RESET"
    else
        printf '%s%s%-12s%s  %s\n' "$NIMO_PAD" "$NIMO_C_DIM" "$1" "$NIMO_C_RESET" "$2"
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
