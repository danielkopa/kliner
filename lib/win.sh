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
# Counting whitespace-separated fields is wrong twice over. A value name may
# hold spaces — `OneDrive Standalone Update Task` is sitting in most people's
# Run key — and so may the data. Blanking the first two fields turned that
# name into two fields and put the rest of the name into the value, so what
# nimo wrote down as the prior value was wrong and `min startup --undo`
# replayed the wrong thing back into the registry.
#
# reg query separates its three columns with four spaces, so the type is the
# only landmark: everything after the first `    REG_TYPE    ` is the data,
# exactly as it stands, runs of spaces and all.
nimo_reg_read() {
    local out line type
    out=$(nimo_reg query "$1" /v "$2" 2>/dev/null) || return 1
    line=$(printf '%s\n' "$out" | grep -i "    REG_" | head -1)
    [ -n "$line" ] || return 1
    type=$(printf '%s' "$line" | grep -o 'REG_[A-Z_]*' | head -1)
    [ -n "$type" ] || return 1
    printf '%s' "${line#*    $type    }" | sed -e 's/[[:space:]]*$//'
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

# ---- PowerShell ----------------------------------------------------------
#
# `reg` covers the settings; a few things Windows only tells you through its
# own shell. A function so the suite can stand a fake one in front of it.
nimo_ps() {
    if nimo_have powershell.exe; then
        powershell.exe -NoProfile -NonInteractive -Command "$1" 2>/dev/null
        return $?
    fi
    if nimo_have powershell; then
        powershell -NoProfile -NonInteractive -Command "$1" 2>/dev/null
        return $?
    fi
    if nimo_have pwsh; then
        pwsh -NoProfile -NonInteractive -Command "$1" 2>/dev/null
        return $?
    fi
    return 1
}

nimo_ps_ready() {
    nimo_have powershell.exe || nimo_have powershell || nimo_have pwsh
}

# The Recycle Bin is not a folder anyone should be reading files out of — it
# is files plus an index. Windows will say what is in it, though, and Windows
# will empty it. nimo asks, and never reaches in.
NIMO_WIN_BIN_COUNT='$b = (New-Object -ComObject Shell.Application).NameSpace(0xA); if ($b -eq $null) { 0 } else { @($b.Items()).Count }'
NIMO_WIN_BIN_SIZE='$b = (New-Object -ComObject Shell.Application).NameSpace(0xA); if ($b -eq $null) { 0 } else { $s = 0; foreach ($i in $b.Items()) { $s += $i.Size }; $s }'

# a number, always — the callers do arithmetic with these
nimo_win_number() {
    local out
    out=$(nimo_ps "$1" 2>/dev/null) || { printf '0'; return 0; }
    out=$(printf '%s' "$out" | tr -d ' \r\n')
    case "$out" in
        ''|*[!0-9]*) printf '0' ;;
        *)           printf '%s' "$out" ;;
    esac
}

nimo_win_bin_count() { nimo_win_number "$NIMO_WIN_BIN_COUNT"; }
nimo_win_bin_kb()    { printf '%s' "$(( $(nimo_win_number "$NIMO_WIN_BIN_SIZE") / 1024 ))"; }

nimo_win_bin_empty() {
    nimo_ps 'Clear-RecycleBin -Force -ErrorAction SilentlyContinue' >/dev/null 2>&1
    return 0
}

# ---- what is installed ---------------------------------------------------
#
# Read only. nimo lists what is on the machine and when it was installed; it
# has never uninstalled anything and this does not start.
NIMO_WIN_APPS='
$keys = @(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
Get-ItemProperty $keys -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
  ForEach-Object {
    "{0}`t{1}`t{2}" -f $_.DisplayName, $_.InstallDate, $_.EstimatedSize
  }'

nimo_win_apps() { nimo_ps "$NIMO_WIN_APPS"; }

# ---- the taskbar ---------------------------------------------------------
#
# Auto-hide is one bit inside a forty-byte blob under StuckRects3, which is
# why this is PowerShell and not `reg`: reading a REG_BINARY back out of
# `reg query` as hex and writing it again is a way to get one byte wrong.
NIMO_WIN_STUCK='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'

nimo_win_taskbar_hidden() {
    local v
    v=$(nimo_win_number "\$v = (Get-ItemProperty -Path '$NIMO_WIN_STUCK' -Name Settings -ErrorAction SilentlyContinue).Settings; if (\$v -eq \$null) { 0 } else { \$v[8] -band 1 }")
    [ "$v" = "1" ] && printf '1' || printf '0'
}

nimo_win_taskbar_hide() {
    local want="$1" op
    if [ "$want" = "1" ]; then op='-bor 1'; else op='-band 254'; fi
    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        printf '  %s$ powershell -Command "…StuckRects3 Settings[8] %s"%s\n' \
            "$NIMO_C_DIM" "$op" "$NIMO_C_RESET"
        return 0
    fi
    nimo_ps "\$p = '$NIMO_WIN_STUCK'; \$v = (Get-ItemProperty -Path \$p -Name Settings -ErrorAction SilentlyContinue).Settings; if (\$v -ne \$null) { \$v[8] = (\$v[8] $op); Set-ItemProperty -Path \$p -Name Settings -Value \$v }" >/dev/null 2>&1
    return 0
}

# The one thing in nimo that restarts Explorer, because the taskbar reads this
# setting when it starts and at no other time. It is asked for separately,
# every time, and it deletes nothing: Windows brings the shell straight back,
# your desktop icons keep their places, and File Explorer has no unsaved work
# to lose.
nimo_win_restart_explorer() {
    nimo_ps 'Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 400; if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }' >/dev/null 2>&1
    return 0
}

# ---- the battery ---------------------------------------------------------
#
# Win32_Battery answers both halves at once. BatteryStatus is a small
# enumeration: 1 is running on the battery, 2 is on mains, 3 is fully charged.
NIMO_WIN_BATTERY='$b = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1; if ($b -eq $null) { "" } else { "{0} {1}" -f $b.EstimatedChargeRemaining, $b.BatteryStatus }'

nimo_win_battery() {
    local raw pct code state
    raw=$(nimo_ps "$NIMO_WIN_BATTERY" 2>/dev/null) || return 1
    raw=$(printf '%s' "$raw" | tr -d '\r' | head -1)
    pct=$(printf '%s' "$raw" | awk '{print $1 + 0}')
    code=$(printf '%s' "$raw" | awk '{print $2 + 0}')
    case "$pct" in ''|0) [ "$pct" = "0" ] && [ -z "$raw" ] && return 1 ;; esac
    [ -n "$raw" ] || return 1

    case "$code" in
        1)  state="on battery" ;;
        2)  state="plugged in" ;;
        3)  state="charged" ;;
        4|5) state="running low" ;;
        6|7|8|9) state="charging" ;;
        *)  state="plugged in" ;;
    esac
    printf '%s%%  ·  %s' "$pct" "$state"
}

# ---- what starts when you sign in ----------------------------------------
#
# Two registry keys and a folder. HKCU is yours; HKLM belongs to the machine
# and needs an administrator, so nimo lists it and never touches it.
NIMO_WIN_RUN='HKCU\Software\Microsoft\Windows\CurrentVersion\Run'
NIMO_WIN_RUN_MACHINE='HKLM\Software\Microsoft\Windows\CurrentVersion\Run'

# `reg query KEY` without /v lists every value under it:
#     Name    REG_SZ    "C:\...\thing.exe"
# One line out per value: name <TAB> command
nimo_win_run_values() {
    nimo_reg query "$1" 2>/dev/null \
        | sed -n 's/^[[:space:]]\{4,\}\([^[:space:]].*\)$/\1/p' \
        | awk -F'    +' 'NF >= 3 { name = $1; cmd = $3; for (i = 4; i <= NF; i++) cmd = cmd "    " $i; print name "\t" cmd }'
}

nimo_win_startup_folder() {
    printf '%s' "$HOME/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup"
}

# ---- the taskbar's pinned apps -------------------------------------------
#
# Pinning is two things at once: a shortcut in a folder, and a blob under
# Taskband that Explorer keeps in step with it. Removing one without the other
# leaves a pin that comes back, or a gap that does not fill — so nimo moves
# the shortcut aside, writes the blob down and clears it, and lets Explorer
# rebuild the blob from the folder when it next starts.
NIMO_WIN_TASKBAND='HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'

nimo_win_pinned_dir() {
    printf '%s' "$HOME/AppData/Roaming/Microsoft/Internet Explorer/Quick Launch/User Pinned/TaskBar"
}

# one line per pin:  name <TAB> the shortcut
nimo_win_pinned() {
    local dir item name
    dir=$(nimo_win_pinned_dir)
    [ -d "$dir" ] || return 0
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        name=$(basename "$item")
        case "$name" in .*|desktop.ini) continue ;; esac
        printf '%s\t%s\n' "${name%.*}" "$item"
    done <<INNER
$(find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.lnk' 2>/dev/null | sort)
INNER
}
