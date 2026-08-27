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

    if ! nimo_is_macos; then
        nimo_warn "appearance is a macOS thing"
        nimo_blank
        return 0
    fi

    local now
    now=$(nimo_dark_now)
    [ -n "$want" ] || { [ "$now" = "dark" ] && want=light || want=dark; }

    nimo_panel_open "appearance"
    nimo_say "$now  →  $want"
    nimo_panel_close

    if [ "$now" = "$want" ]; then
        nimo_dim "already $want — nothing to do"
        nimo_blank
        return 0
    fi

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "preview only — nothing was changed"
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
    nimo_setup_record NSGlobalDomain AppleInterfaceStyle
    nimo_dark_apply "$want"

    nimo_blank
    nimo_ok "$want"
    nimo_dim "back with  min setup --restore"
    nimo_blank
    return 0
}

nimo_cmd_dark()  { nimo_cmd_appearance dark; }
nimo_cmd_light() { nimo_cmd_appearance light; }

# The menu bar is the last thing on a clean screen that never goes away.
nimo_cmd_hide() {
    nimo_header

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
        nimo_dim "already like that — nothing to do"
        nimo_blank
        return 0
    fi

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "\$ defaults write NSGlobalDomain _HIHideMenuBar -bool $([ "$want" = 1 ] && echo true || echo false)"
        nimo_dim "preview only — nothing was changed"
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
