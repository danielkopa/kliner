#!/usr/bin/env bash
# nimo :: lib/setup.sh — opinionated, reversible macOS defaults.
#
# Everything here is a `defaults write`. Nothing is destructive,
# nothing needs sudo, and every group can be applied on its own:
#   min setup --only dock,finder

NIMO_G_ID=(); NIMO_G_LABEL=(); NIMO_G_DESC=()
NIMO_G_N=0

nimo_register_group() {
    NIMO_G_ID[$NIMO_G_N]="$1"
    NIMO_G_LABEL[$NIMO_G_N]="$2"
    NIMO_G_DESC[$NIMO_G_N]="$3"
    NIMO_G_N=$((NIMO_G_N + 1))
}

nimo_register_groups() {
    NIMO_G_ID=(); NIMO_G_LABEL=(); NIMO_G_DESC=()
    NIMO_G_N=0
    nimo_register_group finder      "Finder"      "show extensions, path bar, list view, folders first"
    nimo_register_group dock        "Dock"        "auto-hide instantly, no recent apps, smaller icons"
    nimo_register_group screenshots "Screenshots" "save to ~/Desktop/Screenshots as png, no drop shadow"
    nimo_register_group keyboard    "Keyboard"    "fast key repeat, hold a key to repeat it"
    nimo_register_group dialogs     "Dialogs"     "always expand save and print panels"
}

# run a command, or just show it in dry-run mode
nimo_run() {
    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        printf '  %s$ %s%s\n' "$NIMO_C_DIM" "$*" "$NIMO_C_RESET"
    else
        "$@" >/dev/null 2>&1 || nimo_warn "could not apply: $*"
    fi
}

nimo_group_selected() {
    [ -z "${NIMO_ONLY:-}" ] && return 0
    case ",${NIMO_ONLY}," in
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
}

nimo_apply_finder() {
    nimo_run defaults write NSGlobalDomain AppleShowAllExtensions -bool true
    nimo_run defaults write com.apple.finder ShowPathbar -bool true
    nimo_run defaults write com.apple.finder ShowStatusBar -bool true
    nimo_run defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
    nimo_run defaults write com.apple.finder FXDefaultSearchScope -string SCcf
    nimo_run defaults write com.apple.finder _FXSortFoldersFirst -bool true
    nimo_run defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
    nimo_run defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
    NIMO_RESTART_FINDER=1
}

nimo_apply_dock() {
    nimo_run defaults write com.apple.dock autohide -bool true
    nimo_run defaults write com.apple.dock autohide-delay -float 0
    nimo_run defaults write com.apple.dock autohide-time-modifier -float 0.35
    nimo_run defaults write com.apple.dock show-recents -bool false
    nimo_run defaults write com.apple.dock tilesize -int 42
    nimo_run defaults write com.apple.dock mru-spaces -bool false
    NIMO_RESTART_DOCK=1
}

nimo_apply_screenshots() {
    local dir="$HOME/Desktop/Screenshots"
    nimo_run mkdir -p "$dir"
    nimo_run defaults write com.apple.screencapture location -string "$dir"
    nimo_run defaults write com.apple.screencapture type -string png
    nimo_run defaults write com.apple.screencapture disable-shadow -bool true
    NIMO_RESTART_UI=1
}

nimo_apply_keyboard() {
    nimo_run defaults write NSGlobalDomain KeyRepeat -int 2
    nimo_run defaults write NSGlobalDomain InitialKeyRepeat -int 15
    nimo_run defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
}

nimo_apply_dialogs() {
    nimo_run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
    nimo_run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
    nimo_run defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
    nimo_run defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
}

nimo_apply_group() {
    case "$1" in
        finder)      nimo_apply_finder ;;
        dock)        nimo_apply_dock ;;
        screenshots) nimo_apply_screenshots ;;
        keyboard)    nimo_apply_keyboard ;;
        dialogs)     nimo_apply_dialogs ;;
    esac
}

nimo_setup_list() {
    local i=0
    nimo_title "Setup groups"
    while [ "$i" -lt "$NIMO_G_N" ]; do
        printf '  %-14s %s%s%s\n' "${NIMO_G_ID[$i]}" "$NIMO_C_DIM" "${NIMO_G_DESC[$i]}" "$NIMO_C_RESET"
        i=$((i + 1))
    done
    nimo_blank
    nimo_dim "apply everything:      min setup"
    nimo_dim "apply just a few:      min setup --only dock,finder"
    nimo_dim "see the commands:      min setup --dry-run"
    nimo_blank
}

nimo_cmd_setup() {
    nimo_header
    nimo_register_groups

    if [ "${NIMO_LIST:-0}" = "1" ]; then
        nimo_setup_list
        return 0
    fi

    if ! nimo_is_macos; then
        nimo_warn "min setup only knows how to tune macOS."
        nimo_dim "everything else in nimo works here — try  min clean"
        nimo_blank
        return 0
    fi

    nimo_title "Minimal setup"
    local i=0 planned=0
    while [ "$i" -lt "$NIMO_G_N" ]; do
        if nimo_group_selected "${NIMO_G_ID[$i]}"; then
            printf '  %-14s %s%s%s\n' "${NIMO_G_LABEL[$i]}" "$NIMO_C_DIM" "${NIMO_G_DESC[$i]}" "$NIMO_C_RESET"
            planned=$((planned + 1))
        fi
        i=$((i + 1))
    done

    if [ "$planned" = "0" ]; then
        nimo_blank
        nimo_warn "no matching group — try  min setup --list"
        nimo_blank
        return 1
    fi

    nimo_blank
    nimo_dim "these are preferences only — no files are touched, nothing needs sudo"
    nimo_blank

    if [ "${NIMO_DRY_RUN:-0}" != "1" ]; then
        if ! nimo_confirm "Apply this setup?"; then
            nimo_blank
            nimo_dim "nothing was changed"
            nimo_blank
            return 0
        fi
        nimo_blank
    fi

    NIMO_RESTART_FINDER=0; NIMO_RESTART_DOCK=0; NIMO_RESTART_UI=0
    i=0
    while [ "$i" -lt "$NIMO_G_N" ]; do
        if nimo_group_selected "${NIMO_G_ID[$i]}"; then
            [ "${NIMO_DRY_RUN:-0}" = "1" ] && nimo_title "${NIMO_G_LABEL[$i]}"
            nimo_apply_group "${NIMO_G_ID[$i]}"
        fi
        i=$((i + 1))
    done

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_blank
        nimo_dim "preview only — nothing was changed"
        nimo_blank
        return 0
    fi

    [ "${NIMO_RESTART_FINDER:-0}" = "1" ] && killall Finder >/dev/null 2>&1
    [ "${NIMO_RESTART_DOCK:-0}" = "1" ] && killall Dock >/dev/null 2>&1
    [ "${NIMO_RESTART_UI:-0}" = "1" ] && killall SystemUIServer >/dev/null 2>&1

    nimo_ok "Setup applied."
    nimo_dim "some changes need a logout to show up everywhere"
    nimo_blank
    return 0
}
