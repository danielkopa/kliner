#!/usr/bin/env bash
# nimo :: lib/setup.sh — opinionated, reversible preferences.
#
# Everything here is a `defaults write` on macOS and an HKCU registry value on
# Windows. Nothing is destructive, nothing needs sudo or an administrator, and
# every group can be applied on its own:
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
    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_register_group explorer "Explorer" "show extensions, open to This PC, no ads in the sidebar"
        nimo_register_group taskbar  "Taskbar"  "no task view, no widgets, search as an icon"
        return 0
    fi
    nimo_register_group finder      "Finder"      "show extensions, path bar, list view, folders first"
    nimo_register_group dock        "Dock"        "auto-hide instantly, no recent apps, smaller icons"
    nimo_register_group screenshots "Screenshots" "save to ~/Desktop/Screenshots as png, no drop shadow"
    nimo_register_group keyboard    "Keyboard"    "fast key repeat, hold a key to repeat it"
    nimo_register_group dialogs     "Dialogs"     "always expand save and print panels"
}

NIMO_SETUP_LOG=""

# Write down what a preference was, before changing it.
#
# `defaults read` gives the value but not the type, and writing an integer
# back as a string is not the same setting — so the type is read too, and
# replayed with the matching flag.
nimo_setup_record() {
    local domain="$1" key="$2" prior type
    [ -n "${NIMO_SETUP_LOG:-}" ] || return 0

    prior=$(defaults read "$domain" "$key" 2>/dev/null) || {
        printf '%s\t%s\tabsent\t\t\n' "$domain" "$key" >> "$NIMO_SETUP_LOG"
        return 0
    }

    # Anything with a newline or a tab in it is a structure, not a setting.
    # Note the $'...' quoting: "$(printf '\n')" looks like it says the same
    # thing, but command substitution strips trailing newlines, so it collapses
    # to an empty string and the pattern then matches every value there is.
    case "$prior" in
        *$'\n'*|*$'\t'*)
            printf '%s\t%s\tcomplex\t\t\n' "$domain" "$key" >> "$NIMO_SETUP_LOG"
            return 0 ;;
    esac

    type=$(defaults read-type "$domain" "$key" 2>/dev/null)
    case "$type" in
        *boolean*) type="-bool" ;;
        *integer*) type="-int" ;;
        *float*)   type="-float" ;;
        *)         type="-string" ;;
    esac

    printf '%s\t%s\thad\t%s\t%s\n' "$domain" "$key" "$type" "$prior" >> "$NIMO_SETUP_LOG"
}

# run a command, or just show it in dry-run mode
nimo_run() {
    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        printf '  %s$ %s%s\n' "$NIMO_C_DIM" "$*" "$NIMO_C_RESET"
        return 0
    fi

    if [ "${1:-}" = "defaults" ] && [ "${2:-}" = "write" ]; then
        nimo_setup_record "${3:-}" "${4:-}"
    fi

    "$@" >/dev/null 2>&1 || nimo_warn "could not apply: $*"
}

# shellcheck disable=SC2120  # the log to replay is optional
nimo_setup_restore() {
    [ "${NIMO_UNDO_QUIET:-0}" = "1" ] || nimo_header
    nimo_panel_open "put the preferences back"

    local latest="${1:-}"
    [ -n "$latest" ] || latest=$(nimo_newest "$NIMO_BACKUP_DIR"/setup-*.tsv) || latest=""

    if [ -z "$latest" ] || [ ! -f "$latest" ]; then
        nimo_dim "nimo has not changed any preferences yet"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    # One log, two systems. A line whose type starts with REG_ was written by
    # the Windows side and goes back through the registry; everything else is
    # a `defaults` line. The alternative was two logs and one `min undo` that
    # had to guess which it was looking at.
    local back=0 removed=0 skipped=0 domain key state type value
    while IFS=$'\t' read -r domain key state type value; do
        [ -n "${domain:-}" ] || continue
        [ -n "${key:-}" ] || continue
        case "$state" in
            had)
                case "$type" in
                    REG_*) nimo_reg_write "$domain" "$key" "$type" "$value" ;;
                    *)     defaults write "$domain" "$key" "$type" "$value" >/dev/null 2>&1 ;;
                esac && back=$((back + 1)) ;;
            absent)
                case "$type" in
                    REG_*) nimo_reg_erase "$domain" "$key" ;;
                    *)     defaults delete "$domain" "$key" >/dev/null 2>&1 ;;
                esac
                removed=$((removed + 1)) ;;
            *)
                skipped=$((skipped + 1)) ;;
        esac
    done < "$latest"

    killall Finder >/dev/null 2>&1
    killall Dock >/dev/null 2>&1
    killall SystemUIServer >/dev/null 2>&1

    nimo_ok "$(nimo_plural "$back" preference) back to what it was"
    [ "$removed" -gt 0 ] && nimo_dim "$removed had never been set, and are unset again"
    [ "$skipped" -gt 0 ] && nimo_dim "$skipped were too complicated to replay and were left alone"
    nimo_dim "$(basename "$latest")"
    nimo_panel_close
    nimo_blank
    return 0
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

# Two Explorer settings that make Windows feel like the Mac side of nimo:
# a file manager that tells you what a file is, and a taskbar with only the
# things you put there. Every value is HKCU and written down before it moves.
nimo_apply_explorer() {
    nimo_win_set "$NIMO_WIN_ADVANCED" HideFileExt REG_DWORD 0
    nimo_win_set "$NIMO_WIN_ADVANCED" LaunchTo    REG_DWORD 1
    nimo_win_set "$NIMO_WIN_ADVANCED" ShowSyncProviderNotifications REG_DWORD 0
    NIMO_RESTART_EXPLORER=1
}

nimo_apply_taskbar() {
    nimo_win_set "$NIMO_WIN_ADVANCED" ShowTaskViewButton REG_DWORD 0
    nimo_win_set "$NIMO_WIN_ADVANCED" TaskbarDa          REG_DWORD 0
    nimo_win_set "$NIMO_WIN_ADVANCED" TaskbarMn          REG_DWORD 0
    nimo_win_set "$NIMO_WIN_SEARCH"   SearchboxTaskbarMode REG_DWORD 1
    NIMO_RESTART_EXPLORER=1
}

nimo_apply_group() {
    case "$1" in
        finder)      nimo_apply_finder ;;
        dock)        nimo_apply_dock ;;
        screenshots) nimo_apply_screenshots ;;
        keyboard)    nimo_apply_keyboard ;;
        dialogs)     nimo_apply_dialogs ;;
        explorer)    nimo_apply_explorer ;;
        taskbar)     nimo_apply_taskbar ;;
    esac
}

nimo_setup_list() {
    local i=0
    nimo_title "Setup groups"
    while [ "$i" -lt "$NIMO_G_N" ]; do
        printf '  %-14s %s%s%s\n' "${NIMO_G_ID[$i]}" "$NIMO_C_DIM" "${NIMO_G_DESC[$i]}" "$NIMO_C_RESET"
        i=$((i + 1))
    done
    # the example names groups this computer actually has: on Windows it used
    # to suggest --only dock,finder, neither of which is offered there
    local few="${NIMO_G_ID[0]:-}"
    [ "$NIMO_G_N" -gt 1 ] && few="$few,${NIMO_G_ID[1]}"

    nimo_blank
    nimo_dim "apply everything:      min setup"
    nimo_dim "apply just a few:      min setup --only $few"
    nimo_dim "see the commands:      min setup --dry-run"
    nimo_blank
}

nimo_cmd_setup() {
    if [ "${NIMO_RESTORE:-0}" = "1" ]; then
        nimo_setup_restore
        return 0
    fi

    nimo_header
    nimo_register_groups

    if [ "${NIMO_LIST:-0}" = "1" ]; then
        nimo_setup_list
        return 0
    fi

    case "$(nimo_platform)" in
        macos|windows) ;;
        *)
            nimo_warn "min setup knows how to tune macOS and Windows, not this."
            nimo_dim "everything else in nimo works here, try  min clean"
            nimo_blank
            return 0 ;;
    esac

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
        nimo_warn "no matching group, try  min setup --list"
        nimo_blank
        return 1
    fi

    nimo_blank
    nimo_dim "these are preferences only, no files are touched, nothing needs sudo"
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

    NIMO_RESTART_FINDER=0; NIMO_RESTART_DOCK=0; NIMO_RESTART_UI=0; NIMO_RESTART_EXPLORER=0
    # A preview changes nothing, and an empty log left behind in the backups
    # folder is a change. min startup and min dock both got this right.
    NIMO_SETUP_LOG=""
    if [ "${NIMO_DRY_RUN:-0}" != "1" ]; then
        mkdir -p "$NIMO_BACKUP_DIR" 2>/dev/null
        NIMO_SETUP_LOG=$(nimo_free_file "$NIMO_BACKUP_DIR/setup-$(date +%Y%m%d-%H%M%S)" .tsv)
        : > "$NIMO_SETUP_LOG"
    fi
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
        nimo_dim "preview only, nothing was changed"
        nimo_blank
        return 0
    fi

    [ "${NIMO_RESTART_FINDER:-0}" = "1" ] && killall Finder >/dev/null 2>&1
    [ "${NIMO_RESTART_DOCK:-0}" = "1" ] && killall Dock >/dev/null 2>&1
    [ "${NIMO_RESTART_UI:-0}" = "1" ] && killall SystemUIServer >/dev/null 2>&1
    # Windows gets the documented poke and nothing else. Killing Explorer
    # would apply these a few seconds sooner and close every folder you had
    # open to do it.
    [ "${NIMO_RESTART_EXPLORER:-0}" = "1" ] && nimo_win_refresh

    nimo_ok "Setup applied."
    nimo_dim "some changes need a logout to show up everywhere"
    nimo_dim "changed your mind?  min setup --restore"
    nimo_blank
    return 0
}

# ---- min zen -------------------------------------------------------------
#
# The fastest way to a calm desktop: stop drawing it. Nothing is moved and
# nothing is deleted — Finder simply stops painting icons on the wallpaper,
# and everything is still there in ~/Desktop.

# The same command on Windows. Explorer keeps one value for it, HideIcons,
# and the files on the desktop are not touched either way.
nimo_zen_windows() {
    nimo_panel_open "zen"

    local showing want
    showing=$(nimo_win_icons_showing)
    want=0
    [ "${NIMO_RESTORE:-0}" = "1" ] && want=1

    if [ "$want" = "1" ]; then
        nimo_say "Your desktop icons come back."
    else
        nimo_say "Explorer stops drawing icons on your desktop."
        nimo_blank
        nimo_dim "the files stay exactly where they are, on your Desktop"
        nimo_dim "you reach them in Explorer, or with  min zen --restore"
    fi

    if [ "$showing" = "$want" ]; then
        nimo_blank
        nimo_dim "already like that, nothing to do"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    nimo_panel_close
    nimo_blank

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_win_icons_apply "$want"
        nimo_dim "preview only, nothing was changed"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "$([ "$want" = "1" ] && echo "Show your desktop icons again?" || echo "Hide your desktop icons?")"; then
        nimo_blank
        nimo_dim "nothing was changed"
        nimo_blank
        return 0
    fi

    nimo_look_log
    nimo_win_icons_apply "$want"
    nimo_win_refresh

    nimo_blank
    if [ "$want" = "1" ]; then
        nimo_ok "Your desktop is back."
    else
        nimo_ok "Quiet desktop."
        nimo_dim "bring it back with  min zen --restore"
    fi
    nimo_dim "Explorer picks this up when it next redraws, sign out and back"
    nimo_dim "in if it has not by then"
    nimo_blank
    return 0
}

# The switches System Settings has had since macOS 14, Desktop & Dock › Show
# Items: the Mac fades the icons out and back in at once, and Finder is not
# started again. There are two of them — "On Desktop" and "In Stage Manager" —
# and the Mac reads whichever one matches the mode it is in. nimo writes both.
# One switch on and the other off is how this ends up looking broken: every
# press flips the one nobody is reading, and the icons never move. Prints
# them both; nothing on a Mac older than 14, where Finder's CreateDesktop is
# the only way.
nimo_zen_live_keys() {
    [ "${NIMO_ZEN_FINDER:-0}" = "1" ] && return 1
    local v
    v=$(sw_vers -productVersion 2>/dev/null) || return 1
    [ "${v%%.*}" -ge 14 ] 2>/dev/null || return 1
    printf 'HideDesktop StandardHideDesktopIcons'
}

nimo_cmd_zen() {
    nimo_header

    case "$(nimo_platform)" in
        macos|windows) ;;
        *)
            nimo_warn "hiding desktop icons is a macOS and Windows thing"
            nimo_blank
            return 0 ;;
    esac

    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_zen_windows
        return $?
    fi

    nimo_panel_open "zen"

    # Showing means both: Finder draws the desktop at all, and the Mac's own
    # switch is not hiding it. Either one can be what hid it.
    local showing finder=1 live_keys="" live_off=0 key
    case "$(defaults read com.apple.finder CreateDesktop 2>/dev/null)" in
        0|false|no) finder=0 ;;
    esac
    live_keys=$(nimo_zen_live_keys) || live_keys=""
    for key in $live_keys; do
        case "$(defaults read com.apple.WindowManager "$key" 2>/dev/null)" in
            1|true|yes) live_off=1 ;;
        esac
    done
    showing=1
    { [ "$finder" = 0 ] || [ "$live_off" = 1 ]; } && showing=0

    local want=0
    [ "${NIMO_RESTORE:-0}" = "1" ] && want=1

    if [ "$want" = "1" ]; then
        nimo_say "Your desktop icons come back."
    else
        nimo_say "The icons on your desktop go."
        nimo_blank
        nimo_dim "the files stay exactly where they are, in ~/Desktop"
        nimo_dim "you reach them in Finder, or with  min zen --restore"
    fi

    if [ "$showing" = "$want" ]; then
        nimo_blank
        nimo_dim "already like that, nothing to do"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    nimo_panel_close
    nimo_blank

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        if [ -n "$live_keys" ]; then
            for key in $live_keys; do
                nimo_dim "\$ defaults write com.apple.WindowManager $key -bool $([ "$want" = 1 ] && echo false || echo true)"
            done
            [ "$want" = 1 ] && [ "$finder" = 0 ] \
                && nimo_dim "\$ defaults write com.apple.finder CreateDesktop -bool true"
        else
            nimo_dim "\$ defaults write com.apple.finder CreateDesktop -bool $([ "$want" = 1 ] && echo true || echo false)"
        fi
        nimo_dim "preview only, nothing was changed"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "$([ "$want" = "1" ] && echo "Show your desktop icons again?" || echo "Hide your desktop icons?")"; then
        nimo_blank
        nimo_dim "nothing was changed"
        nimo_blank
        return 0
    fi

    mkdir -p "$NIMO_BACKUP_DIR" 2>/dev/null
    NIMO_SETUP_LOG=$(nimo_free_file "$NIMO_BACKUP_DIR/setup-$(date +%Y%m%d-%H%M%S)" .tsv)
    : > "$NIMO_SETUP_LOG"

    if [ "$want" = "1" ]; then
        # the Mac's switches first, which is instant; Finder only if it was
        # Finder that stopped drawing them, since only a new Finder draws again
        for key in $live_keys; do
            case "$(defaults read com.apple.WindowManager "$key" 2>/dev/null)" in
                1|true|yes) nimo_run defaults write com.apple.WindowManager "$key" -bool false ;;
            esac
        done
        if [ "$finder" = 0 ]; then
            nimo_run defaults write com.apple.finder CreateDesktop -bool true
            killall Finder >/dev/null 2>&1
        fi
    elif [ -n "$live_keys" ]; then
        for key in $live_keys; do
            nimo_run defaults write com.apple.WindowManager "$key" -bool true
        done
    else
        nimo_run defaults write com.apple.finder CreateDesktop -bool false
        killall Finder >/dev/null 2>&1
    fi

    nimo_blank
    if [ "$want" = "1" ]; then
        nimo_ok "Your desktop is back."
    else
        nimo_ok "Quiet desktop."
        nimo_dim "bring it back with  min zen --restore"
    fi
    nimo_blank
    return 0
}
