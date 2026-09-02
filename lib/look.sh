#!/usr/bin/env bash
# nimo :: lib/look.sh — the two switches that change how a Mac feels.
#
# Both are preferences, both are written down before they are touched, and
# both come back with min undo like everything else.

# Start a preference log, so whatever follows can be undone.
nimo_look_log() {
    mkdir -p "$NIMO_BACKUP_DIR" 2>/dev/null
    NIMO_SETUP_LOG=$(nimo_free_file "$NIMO_BACKUP_DIR/setup-$(date +%Y%m%d-%H%M%S)" .tsv)
    : > "$NIMO_SETUP_LOG"
}

nimo_dark_now() {
    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_win_dark_now
        return 0
    fi
    local style
    style=$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null) || style=""
    case "$style" in
        Dark|dark) printf 'dark' ;;
        *)         printf 'light' ;;
    esac
}

# osascript changes it there and then; defaults is the fallback, and either
# way the old value is already written down.
nimo_dark_apply() {
    local want="$1"
    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_win_dark_apply "$want"
        return 0
    fi
    if osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $([ "$want" = dark ] && echo true || echo false)" >/dev/null 2>&1; then
        return 0
    fi
    if [ "$want" = "dark" ]; then
        defaults write NSGlobalDomain AppleInterfaceStyle -string Dark >/dev/null 2>&1
    else
        defaults delete NSGlobalDomain AppleInterfaceStyle >/dev/null 2>&1
    fi
    killall SystemUIServer >/dev/null 2>&1
    return 0
}

# $1 is the appearance to end up in, or empty to swap
nimo_cmd_appearance() {
    local want="${1:-}"
    nimo_header

    case "$(nimo_platform)" in
        macos|windows) ;;
        *)
            nimo_warn "appearance is a macOS and Windows thing"
            nimo_blank
            return 0 ;;
    esac

    local now
    now=$(nimo_dark_now)
    [ -n "$want" ] || { [ "$now" = "dark" ] && want=light || want=dark; }

    nimo_panel_open "appearance"
    nimo_say "$now  →  $want"
    nimo_panel_close

    if [ "$now" = "$want" ]; then
        nimo_dim "already $want, nothing to do"
        nimo_blank
        return 0
    fi

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "preview only, nothing was changed"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "Switch to $want?"; then
        nimo_blank
        nimo_dim "left as it was"
        nimo_blank
        return 0
    fi

    nimo_look_log
    [ "$(nimo_platform)" = "macos" ] && nimo_setup_record NSGlobalDomain AppleInterfaceStyle
    nimo_dark_apply "$want"

    nimo_blank
    nimo_ok "$want"
    nimo_dim "back with  min setup --restore"
    nimo_blank
    return 0
}

nimo_cmd_dark()  { nimo_cmd_appearance dark; }
nimo_cmd_light() { nimo_cmd_appearance light; }

# The Windows counterpart: the taskbar, which slides away the same way.
#
# The setting is one bit inside StuckRects3, and the taskbar reads that blob
# when Explorer starts and at no other time. So this is the one place in nimo
# that restarts Explorer — asked for separately, and never as a side effect of
# something else. Nothing is deleted by it: Windows brings the shell straight
# back, the desktop icons keep their places, and a file browser has no unsaved
# work to lose.
nimo_hide_windows() {
    if ! nimo_ps_ready; then
        nimo_warn "nimo needs PowerShell to reach the taskbar, and cannot find it"
        nimo_blank
        return 1
    fi

    local hidden want
    hidden=$(nimo_win_taskbar_hidden)
    want=1
    [ "${NIMO_RESTORE:-0}" = "1" ] && want=0

    nimo_panel_open "the taskbar"
    if [ "$want" = "1" ]; then
        nimo_say "It slides away until you reach for it."
    else
        nimo_say "It stays put again."
    fi
    nimo_panel_close

    if [ "$hidden" = "$want" ]; then
        nimo_dim "already like that, nothing to do"
        nimo_blank
        return 0
    fi

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_blank
        nimo_win_taskbar_hide "$want"
        nimo_dim "preview only, nothing was changed"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "$([ "$want" = 1 ] && echo "Hide the taskbar?" || echo "Bring the taskbar back?")"; then
        nimo_blank
        nimo_dim "left as it was"
        nimo_blank
        return 0
    fi

    nimo_win_taskbar_hide "$want"

    nimo_blank
    nimo_ok "$([ "$want" = 1 ] && echo "Set to slide away." || echo "Set to stay put.")"
    nimo_blank
    nimo_dim "the taskbar reads this when Explorer starts, so it needs a restart"
    nimo_dim "nothing is lost by that, no files, no icon positions, no windows"
    nimo_dim "with unsaved work. Signing out and back in does the same thing."
    nimo_blank

    if nimo_confirm "Restart Explorer now?"; then
        nimo_win_restart_explorer
        nimo_blank
        nimo_ok "Done."
    else
        nimo_blank
        nimo_dim "it will take effect the next time you sign in"
    fi
    [ "$want" = "1" ] && nimo_dim "back with  min hide --restore"
    nimo_blank
    return 0
}

# The menu bar is the last thing on a clean screen that never goes away.
nimo_cmd_hide() {
    nimo_header

    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_hide_windows
        return $?
    fi

    if ! nimo_is_macos; then
        nimo_warn "the menu bar is a macOS thing"
        nimo_blank
        return 0
    fi

    local hidden want
    hidden=$(defaults read NSGlobalDomain _HIHideMenuBar 2>/dev/null) || hidden=0
    case "$hidden" in
        1|true|yes) hidden=1 ;;
        *)          hidden=0 ;;
    esac

    want=1
    [ "${NIMO_RESTORE:-0}" = "1" ] && want=0

    nimo_panel_open "the menu bar"
    if [ "$want" = "1" ]; then
        nimo_say "It slides away until you reach for it."
    else
        nimo_say "It stays put again."
    fi
    nimo_panel_close

    if [ "$hidden" = "$want" ]; then
        nimo_dim "already like that, nothing to do"
        nimo_blank
        return 0
    fi

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "\$ defaults write NSGlobalDomain _HIHideMenuBar -bool $([ "$want" = 1 ] && echo true || echo false)"
        nimo_dim "preview only, nothing was changed"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "$([ "$want" = 1 ] && echo "Hide the menu bar?" || echo "Bring the menu bar back?")"; then
        nimo_blank
        nimo_dim "left as it was"
        nimo_blank
        return 0
    fi

    nimo_look_log
    if [ "$want" = "1" ]; then
        nimo_run defaults write NSGlobalDomain _HIHideMenuBar -bool true
    else
        nimo_run defaults write NSGlobalDomain _HIHideMenuBar -bool false
    fi
    killall SystemUIServer >/dev/null 2>&1
    killall Finder >/dev/null 2>&1

    nimo_blank
    if [ "$want" = "1" ]; then
        nimo_ok "Gone until you reach for it."
        nimo_dim "back with  min hide --restore"
    else
        nimo_ok "Back where it was."
    fi
    nimo_blank
    return 0
}
