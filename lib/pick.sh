#!/usr/bin/env bash
# nimo :: lib/pick.sh — choosing things with the arrow keys.
#
# Pure bash, no curses, no dependencies. If the terminal cannot do it —
# a pipe, a script, a dumb TERM — everything falls back to typing numbers,
# so nothing ever becomes impossible, only less pleasant.

nimo_pick_capable() {
    [ "${NIMO_PICK_FORCE:-0}" = "1" ] && return 0
    [ -t 0 ] || return 1
    [ -t 1 ] || return 1
    case "${TERM:-}" in dumb|"") return 1 ;; esac
    return 0
}

# Read one keypress, and turn arrow escapes into words.
nimo_read_key() {
    local key rest
    IFS= read -rsn1 key 2>/dev/null || return 1
    case "$key" in
        '')
            printf 'enter'; return 0 ;;
        ' ')
            printf 'space'; return 0 ;;
        $'\033')
            IFS= read -rsn2 -t 1 rest 2>/dev/null
            case "$rest" in
                '[A') printf 'up' ;;
                '[B') printf 'down' ;;
                '[C') printf 'right' ;;
                '[D') printf 'left' ;;
                *)    printf 'escape' ;;
            esac
            return 0 ;;
        k) printf 'up' ;;
        j) printf 'down' ;;
        q) printf 'quit' ;;
        a) printf 'all' ;;
        n) printf 'none' ;;
        # the wallpaper browser's own two; a picker that does not know them
        # simply ignores them, the way it ignores every other letter
        p) printf 'prev' ;;
        r) printf 'random' ;;
        *) printf 'other' ;;
    esac
    return 0
}

# nimo_pick <mode> <hint> <items…as one newline string>
#
#   mode multi  -> prints the numbers of everything ticked, space separated
#   mode single -> prints one number
#
# Anything it draws goes to stderr, so the caller can read the answer from
# stdout without the menu landing in it.
nimo_pick() {
    local mode="$1" hint="$2" items="$3"

    local labels=() n=0 line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        labels[$n]="$line"
        n=$((n + 1))
    done <<EOF
$items
EOF

    [ "$n" -gt 0 ] || return 1

    if ! nimo_pick_capable; then
        # The fallback used to ask "Which one? (1-7):" without ever printing
        # what 1 to 7 were. Every place the arrow keys cannot run — a pipe, a
        # script, ssh without a tty, TERM=dumb — the question was unanswerable,
        # and `min clear` was the command it happened to most.
        local j=0
        printf '\n' >&2
        while [ "$j" -lt "$n" ]; do
            printf '  %s%2d%s  %s\n' "$NIMO_C_DIM" "$((j + 1))" "$NIMO_C_RESET" "${labels[$j]}" >&2
            j=$((j + 1))
        done
        printf '\n' >&2
        nimo_pick_by_number "$mode" "$hint" "$n"
        return $?
    fi

    local marks=() i=0
    while [ "$i" -lt "$n" ]; do marks[$i]=0; i=$((i + 1)); done

    local cursor=0 drawn=0 key

    # ctrl-c in the middle of a pick used to leave the terminal with no cursor
    # until the next `reset`. Whatever happens, it comes back.
    trap 'printf "\033[?25h" >&2' EXIT INT TERM
    printf '\033[?25l' >&2
    nimo_pick_draw() {
        [ "$drawn" -eq 1 ] && printf '\033[%dA' "$((n + 2))" >&2
        local j=0 pointer box row_a row_b
        printf '  %s%s%s\033[K\n\n' "$NIMO_C_DIM" "$hint" "$NIMO_C_RESET" >&2
        while [ "$j" -lt "$n" ]; do
            if [ "$j" -eq "$cursor" ]; then
                pointer="${NIMO_C_CYAN}▸${NIMO_C_RESET}"
                row_a="$NIMO_C_BOLD"
                row_b="$NIMO_C_RESET"
            else
                pointer=" "
                row_a=""
                row_b=""
            fi
            if [ "$mode" = "multi" ]; then
                if [ "${marks[$j]}" = "1" ]; then box="${NIMO_C_CYAN}[x]${NIMO_C_RESET} "; else box="[ ] "; fi
            else
                box=""
            fi
            printf '  %s %s%s%s%s\033[K\n' "$pointer" "$box" "$row_a" "${labels[$j]}" "$row_b" >&2
            j=$((j + 1))
        done
        drawn=1
    }

    nimo_pick_draw
    while :; do
        key=$(nimo_read_key) || key=quit
        case "$key" in
            up)    cursor=$((cursor - 1)); [ "$cursor" -lt 0 ] && cursor=$((n - 1)) ;;
            down)  cursor=$((cursor + 1)); [ "$cursor" -ge "$n" ] && cursor=0 ;;
            space)
                if [ "$mode" = "multi" ]; then
                    if [ "${marks[$cursor]}" = "1" ]; then marks[$cursor]=0; else marks[$cursor]=1; fi
                fi
                ;;
            all)
                if [ "$mode" = "multi" ]; then
                    i=0; while [ "$i" -lt "$n" ]; do marks[$i]=1; i=$((i + 1)); done
                fi
                ;;
            none)
                if [ "$mode" = "multi" ]; then
                    i=0; while [ "$i" -lt "$n" ]; do marks[$i]=0; i=$((i + 1)); done
                fi
                ;;
            enter)
                printf '\033[?25h' >&2
                if [ "$mode" = "multi" ]; then
                    local out="" j=0
                    while [ "$j" -lt "$n" ]; do
                        [ "${marks[$j]}" = "1" ] && out="$out $((j + 1))"
                        j=$((j + 1))
                    done
                    printf '%s' "${out# }"
                else
                    printf '%s' "$((cursor + 1))"
                fi
                return 0
                ;;
            quit|escape)
                printf '\033[?25h' >&2
                return 1
                ;;
        esac
        nimo_pick_draw
    done
}

# The fallback: the same question, answered by typing.
nimo_pick_by_number() {
    local mode="$1" hint="$2" n="$3" answer="" clean="" x

    if [ "$mode" = "multi" ]; then
        printf '  Numbers, separated by spaces — or  all  (enter for none): ' >&2
    else
        printf '  Which one? 1-%s (enter to cancel): ' "$n" >&2
    fi
    # a closed stdin ends this by itself — no need to check for a terminal
    read -r answer || return 1

    # "all" is the typed spelling of the a key the arrow picker takes
    if [ "$mode" = "multi" ]; then
        case "$answer" in
            all|ALL|a)
                x=1
                while [ "$x" -le "$n" ]; do clean="$clean $x"; x=$((x + 1)); done
                printf '%s' "${clean# }"
                return 0 ;;
        esac
    fi

    for x in $(printf '%s' "$answer" | tr ',' ' '); do
        case "$x" in
            ''|*[!0-9]*) continue ;;
        esac
        [ "$x" -ge 1 ] 2>/dev/null || continue
        [ "$x" -le "$n" ] 2>/dev/null || continue
        clean="$clean $x"
        [ "$mode" = "single" ] && break
    done

    printf '%s' "${clean# }"
    return 0
}
