#!/usr/bin/env bash
# nimo :: lib/win.sh — the Windows half of the settings nimo touches.
#
# Everything here lives under HKCU: the signed-in user's own preferences, the
# exact counterpart of `defaults` on a Mac. Nothing under HKLM, nothing that
# needs an administrator, and nothing that deletes a file. Every value nimo
# changes is written down first, in the same log `min undo` already replays.

# `reg` is a function so the suite can stand a fake one in front of it and
# check what nimo would have written, on a machine that is not Windows.
nimo_reg() { reg "$@"; }

# Where Windows itself lives, as a path this shell can read.
#   C:\WINDOWS  ->  /c/WINDOWS
nimo_win_dir() {
    local root="${SYSTEMROOT:-${WINDIR:-}}" drive rest
    if [ -n "$root" ]; then
        # already a path this shell can open
        case "$root" in
            /*) printf '%s' "$root"; return 0 ;;
        esac
        if nimo_have cygpath; then
            cygpath -u "$root" 2>/dev/null && return 0
        fi
        # C:\WINDOWS -> /c/WINDOWS, without cygpath and without GNU sed:
        # the \L and \U escapes are not in BSD sed, and this file is read on
        # a Mac every time the suite runs.
        drive=$(printf '%s' "${root%%:*}" | tr '[:upper:]' '[:lower:]')
        rest=$(printf '%s' "${root#*:}" | tr '\\' '/')
        printf '/%s%s' "$drive" "$rest"
        return 0
    fi
    printf '/c/Windows'
}

# The other direction, for the values Windows itself has to read back.
nimo_win_path() {
    local p="$1" drive rest
    if nimo_have cygpath; then
        cygpath -w "$p" 2>/dev/null && return 0
    fi
    case "$p" in
        /?/*)
            drive=$(printf '%s' "$p" | cut -c2 | tr '[:lower:]' '[:upper:]')
            rest=$(printf '%s' "$p" | cut -c3- | tr '/' '\\')
            printf '%s:%s' "$drive" "$rest" ;;
        *)
            printf '%s' "$p" | tr '/' '\\' ;;
    esac
}

# reg query prints:      ValueName    REG_DWORD    0x1
# and nothing useful at all when the value is not there.
nimo_reg_read() {
    local out line
    out=$(nimo_reg query "$1" /v "$2" 2>/dev/null) || return 1
    line=$(printf '%s\n' "$out" | grep -i "    REG_" | head -1)
    [ -n "$line" ] || return 1
    printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | awk '{ $1 = ""; $2 = ""; sub(/^[[:space:]]+/, ""); print }'
}

nimo_reg_type() {
    local out line
    out=$(nimo_reg query "$1" /v "$2" 2>/dev/null) || return 1
    line=$(printf '%s\n' "$out" | grep -io 'REG_[A-Z_]*' | head -1)
    [ -n "$line" ] || return 1
    printf '%s' "$line"
}

# A DWORD comes back as 0x1. Everything downstream wants a number.
nimo_reg_number() {
    local raw
    raw=$(nimo_reg_read "$1" "$2") || return 1
    case "$raw" in
        0x*|0X*) printf '%s' "$((raw))" ;;
        ''|*[!0-9]*) return 1 ;;
        *) printf '%s' "$raw" ;;
    esac
}

nimo_reg_write()  { nimo_reg add "$1" /v "$2" /t "$3" /d "$4" /f >/dev/null 2>&1; }
nimo_reg_erase()  { nimo_reg delete "$1" /v "$2" /f >/dev/null 2>&1; }

# The same shape of line lib/setup.sh already writes, so one undo replays both:
#   key <TAB> name <TAB> had|absent <TAB> type <TAB> value
nimo_win_record() {
    local key="$1" name="$2" prior type
    [ -n "${NIMO_SETUP_LOG:-}" ] || return 0

    # REG_NONE, not an empty type. The restore decides which system a line
    # came from by whether the type starts with REG_, and a value that was
    # never set still has to be unset through the registry rather than handed
    # to `defaults`, which is not there.
    prior=$(nimo_reg_read "$key" "$name" 2>/dev/null) || {
        printf '%s\t%s\tabsent\tREG_NONE\t\n' "$key" "$name" >> "$NIMO_SETUP_LOG"
        return 0
    }
    type=$(nimo_reg_type "$key" "$name" 2>/dev/null) || type="REG_SZ"
    printf '%s\t%s\thad\t%s\t%s\n' "$key" "$name" "$type" "$prior" >> "$NIMO_SETUP_LOG"
}

# Write down, then write. Dry run shows the command and changes nothing.
nimo_win_set() {
    local key="$1" name="$2" type="$3" value="$4"
    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        printf '  %s$ reg add "%s" /v %s /t %s /d %s /f%s\n' \
            "$NIMO_C_DIM" "$key" "$name" "$type" "$value" "$NIMO_C_RESET"
        return 0
    fi
    nimo_win_record "$key" "$name"
    nimo_reg_write "$key" "$name" "$type" "$value" \
        || nimo_warn "could not set $name"
}

# ---- the settings themselves --------------------------------------------

NIMO_WIN_THEMES='HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
NIMO_WIN_ADVANCED='HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
NIMO_WIN_DESKTOP='HKCU\Control Panel\Desktop'
NIMO_WIN_SEARCH='HKCU\Software\Microsoft\Windows\CurrentVersion\Search'

# 1 means "use the light theme", so the reading is backwards on purpose.
nimo_win_dark_now() {
    local v
    v=$(nimo_reg_number "$NIMO_WIN_THEMES" AppsUseLightTheme) || { printf 'light'; return 0; }
    if [ "$v" = "0" ]; then printf 'dark'; else printf 'light'; fi
}

nimo_win_dark_apply() {
    local want="$1" v=1
    [ "$want" = "dark" ] && v=0
    nimo_win_set "$NIMO_WIN_THEMES" AppsUseLightTheme   REG_DWORD "$v"
    nimo_win_set "$NIMO_WIN_THEMES" SystemUsesLightTheme REG_DWORD "$v"
    return 0
}

nimo_win_icons_showing() {
    local v
    # HideIcons, so 1 means hidden and missing means showing
    v=$(nimo_reg_number "$NIMO_WIN_ADVANCED" HideIcons) || { printf '1'; return 0; }
    if [ "$v" = "1" ]; then printf '0'; else printf '1'; fi
}

nimo_win_icons_apply() {
    local show="$1" hide=1
    [ "$show" = "1" ] && hide=0
    nimo_win_set "$NIMO_WIN_ADVANCED" HideIcons REG_DWORD "$hide"
    return 0
}

# Windows reads most of these back when it is told to, not when they change.
# This is the documented poke, and it is the whole of it — nimo does not kill
# Explorer out from under your open windows to make a setting take.
nimo_win_refresh() {
    [ "${NIMO_DRY_RUN:-0}" = "1" ] && return 0
    RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters >/dev/null 2>&1 \
        || rundll32.exe user32.dll,UpdatePerUserSystemParameters >/dev/null 2>&1 \
        || return 1
    return 0
}
