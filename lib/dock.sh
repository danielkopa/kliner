#!/usr/bin/env bash
# nimo :: lib/dock.sh — a Dock with only the things you actually open.
#
# nimo shows you what is down there, you say what goes. It never removes
# anything on its own, and it exports the whole Dock first, so
# `min dock --restore` brings back exactly what you had.

NIMO_BACKUP_DIR="$HOME/.nimo/backups"

# Apple puts these in every new Dock. Marked as a hint, never removed for you.
nimo_dock_is_stock() {
    case "$1" in
        TV|Podcasts|News|Freeform|Maps|Contacts|Reminders|FaceTime|Launchpad|"App Store"|Keynote|Numbers|Pages|Stocks|Home)
            return 0 ;;
    esac
    return 1
}

# file:///Applications/Google%20Chrome.app/ -> Google Chrome
nimo_dock_name() {
    local url="$1" name
    name="${url%/}"
    name="${name##*/}"
    name="${name%.app}"
    printf '%s' "$name" | sed -e 's/%20/ /g' -e 's/%26/\&/g' -e "s/%27/'/g"
}

nimo_dock_urls() {
    defaults read com.apple.dock persistent-apps 2>/dev/null \
        | grep '_CFURLString"' \
        | sed -e 's/^.*_CFURLString" = "//' -e 's/";[[:space:]]*$//'
}

nimo_dock_backup() {
    mkdir -p "$NIMO_BACKUP_DIR" 2>/dev/null
    local file
    file="$NIMO_BACKUP_DIR/dock-$(date +%Y%m%d-%H%M%S).plist"
    if defaults export com.apple.dock "$file" 2>/dev/null; then
        printf '%s' "$file"
        return 0
    fi
    return 1
}

# shellcheck disable=SC2120  # the backup to restore is optional
nimo_dock_restore() {
    [ "${NIMO_UNDO_QUIET:-0}" = "1" ] || nimo_header
    nimo_panel_open "put the dock back"

    local latest="${1:-}"
    [ -n "$latest" ] || latest=$(ls -1 "$NIMO_BACKUP_DIR"/dock-*.plist 2>/dev/null | tail -1)

    if [ -z "$latest" ]; then
        nimo_dim "no dock backup yet — nimo has not changed your dock"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    if defaults import com.apple.dock "$latest" 2>/dev/null; then
        killall Dock >/dev/null 2>&1
        nimo_ok "Dock restored"
        nimo_dim "$(basename "$latest")"
    else
        nimo_warn "could not restore the dock"
        nimo_dim "the backup is still here: $latest"
    fi

    nimo_panel_close
    nimo_blank
    return 0
}

# rebuild persistent-apps from the urls on stdin
nimo_dock_rewrite() {
    local url
    defaults write com.apple.dock persistent-apps -array 2>/dev/null
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        defaults write com.apple.dock persistent-apps -array-add \
            "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$url</string><key>_CFURLStringType</key><integer>15</integer></dict></dict><key>tile-type</key><string>file-tile</string></dict>" \
            2>/dev/null
    done
    killall Dock >/dev/null 2>&1
    return 0
}

nimo_cmd_dock() {
    if [ "${NIMO_RESTORE:-0}" = "1" ]; then
        nimo_dock_restore
        return 0
    fi

    nimo_header

    if ! nimo_is_macos; then
        nimo_warn "the Dock is a macOS thing"
        nimo_blank
        return 0
    fi

    local urls count
    urls=$(nimo_dock_urls)
    count=$(nimo_line_count "$urls")

    nimo_panel_open "your dock"

    if [ "$count" -eq 0 ]; then
        nimo_dim "nimo cannot read your dock — nothing was changed"
        nimo_panel_close
        nimo_blank
        return 1
    fi

    local labels="" i=1 url name hint
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        name=$(nimo_dock_name "$url")
        hint=""
        nimo_dock_is_stock "$name" && hint="came with macOS"
        labels="$labels$(printf '%-24s %s' "$name" "$hint")
"
        i=$((i + 1))
    done <<EOF
$urls
EOF

    if [ "${NIMO_LIST:-0}" = "1" ] || [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        i=1
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            printf '%s%s%2d%s  %s\n' "$NIMO_PAD" "$NIMO_C_DIM" "$i" "$NIMO_C_RESET" "$name"
            i=$((i + 1))
        done <<EOF
$labels
EOF
        nimo_blank
        nimo_rule
        nimo_total "In your dock" "$(nimo_plural "$count" app)"
        nimo_panel_close
        nimo_blank
        nimo_dim "run  min dock  to pick what goes"
        nimo_blank
        return 0
    fi

    nimo_dim "$(nimo_plural "$count" app) in your dock. tick the ones that should go."
    nimo_blank

    local wanted=""
    if ! wanted=$(nimo_pick multi "↑↓ move   space tick   a all   n none   enter confirm   q cancel" "$labels"); then
        nimo_panel_close
        nimo_blank
        nimo_dim "your dock is exactly as it was"
        nimo_blank
        return 0
    fi
    nimo_panel_close

    if [ -z "$(printf '%s' "$wanted" | tr -d ' ')" ]; then
        nimo_blank
        nimo_dim "nothing ticked — your dock is exactly as it was"
        nimo_blank
        return 0
    fi

    # work out what stays
    local keep="" drop="" n
    i=1
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        local remove=0
        for n in $wanted; do
            case "$n" in
                ''|*[!0-9]*) continue ;;
            esac
            [ "$n" = "$i" ] && remove=1
        done
        if [ "$remove" = "1" ]; then
            drop="$drop$(nimo_dock_name "$url")
"
        else
            keep="$keep$url
"
        fi
        i=$((i + 1))
    done <<EOF
$urls
EOF

    local dropped
    dropped=$(nimo_line_count "$drop")
    if [ "$dropped" -eq 0 ]; then
        nimo_blank
        nimo_dim "those numbers matched nothing — your dock is as it was"
        nimo_blank
        return 0
    fi

    nimo_blank
    nimo_say "Leaving your dock:"
    printf '%s' "$drop" | while IFS= read -r name; do
        [ -n "$name" ] && nimo_dim "  $name"
    done
    nimo_blank
    nimo_dim "the apps stay installed — only the dock icons go"
    nimo_blank

    if ! nimo_confirm "Rebuild your dock without them?"; then
        nimo_blank
        nimo_dim "your dock is exactly as it was"
        nimo_blank
        return 0
    fi

    local backup
    backup=$(nimo_dock_backup) || backup=""
    if [ -z "$backup" ]; then
        nimo_err "could not back up your dock — refusing to change it"
        nimo_blank
        return 1
    fi

    printf '%s' "$keep" | nimo_dock_rewrite

    nimo_blank
    nimo_ok "Dock rebuilt — $(nimo_plural "$dropped" app) fewer"
    nimo_dim "backup: $(basename "$backup")   ·   undo with  min dock --restore"
    nimo_blank
    return 0
}
