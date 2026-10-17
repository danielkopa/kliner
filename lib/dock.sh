#!/usr/bin/env bash
# nimo :: lib/dock.sh — a Dock with only the things you actually open.
#
# nimo shows you what is down there, you say what goes. It never removes
# anything on its own, and it exports the whole Dock first, so
# `min dock --restore` brings back exactly what you had.

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

# file:///Applications/Google%20Chrome.app/ -> /Applications/Google Chrome.app
# Every %XX back to the byte it stands for. A backslash in a name is doubled
# first, so printf keeps it as the one it was.
nimo_dock_path() {
    local path="${1#file://}"
    path="${path%/}"
    case "$path" in
        /*) ;;
        *) return 0 ;;
    esac
    path=$(printf '%s' "$path" | sed -e 's/\\/\\\\/g' -e 's/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')
    printf '%b' "$path"
}

# /Applications/Google Chrome.app -> file:///Applications/Google%20Chrome.app/
# The way the Dock itself writes one down: every byte that is not a letter,
# a digit or one of / . _ ~ - as %XX.
nimo_dock_url() {
    local LC_ALL=C
    local path="$1" out="" c i=0
    while [ "$i" -lt "${#path}" ]; do
        c="${path:$i:1}"
        case "$c" in
            [A-Za-z0-9/._~-]) out="$out$c" ;;
            *) out="$out$(printf '%%%02X' "'$c")" ;;
        esac
        i=$((i + 1))
    done
    printf 'file://%s/' "$out"
}

# Where apps are installed, in the order a name is looked for. nimo only
# reads these folders: an app goes into the Dock as a line in the Dock's own
# preferences, and the app itself is not touched. NIMO_APP_DIRS is for the
# tests, which have no /Applications.
nimo_dock_app_dirs() {
    if [ -n "${NIMO_APP_DIRS:-}" ]; then
        printf '%s\n' "$NIMO_APP_DIRS" | tr ':' '\n'
        return 0
    fi
    printf '%s\n' /Applications /Applications/Utilities /System/Applications \
        /System/Applications/Utilities "$HOME/Applications"
}

# Every app installed in those places, by name, a tab, and where it is. One
# line per name: the first place that has it wins, the way it is looked for.
nimo_dock_installed() {
    local dir app tab
    tab=$(printf '\t')
    nimo_dock_app_dirs | while IFS= read -r dir; do
        [ -d "$dir" ] || continue
        for app in "$dir"/*.app; do
            [ -d "$app" ] || continue
            printf '%s\t%s\n' "$(basename "$app" .app)" "$app"
        done
    done | awk -F "$tab" '!seen[tolower($1)]++' | LC_ALL=C sort -f
}

# Whether an app is already in the dock whose urls come in on stdin.
nimo_dock_holds() {
    local want="$1" url
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        [ "$(nimo_dock_path "$url")" = "$want" ] && return 0
    done
    return 1
}

nimo_dock_urls() {
    defaults read com.apple.dock persistent-apps 2>/dev/null \
        | grep '_CFURLString"' \
        | sed -e 's/^.*_CFURLString" = "//' -e 's/";[[:space:]]*$//'
}

nimo_dock_backup() {
    mkdir -p "$NIMO_BACKUP_DIR" 2>/dev/null
    local file
    file=$(nimo_free_file "$NIMO_BACKUP_DIR/dock-$(date +%Y%m%d-%H%M%S)" .plist)
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
    [ -n "$latest" ] || latest=$(nimo_newest "$NIMO_BACKUP_DIR"/dock-*.plist) || latest=""

    if [ -z "$latest" ]; then
        nimo_dim "no dock backup yet, nimo has not changed your dock"
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

# The dock's auto-hide has a wait built into it, and the slide itself is
# slower than it needs to be. Two preferences fix both, and both are written
# down first, so min undo puts the sluggish version back.
nimo_cmd_dock_fast() {
    nimo_header

    if ! nimo_is_macos; then
        nimo_warn "the Dock is a macOS thing"
        nimo_blank
        return 0
    fi

    nimo_panel_open "a dock that keeps up"
    nimo_say "No wait before it slides, and a slide that takes 0.15s instead of half a second."
    nimo_blank
    nimo_dim "defaults write com.apple.dock autohide-delay -float 0"
    nimo_dim "defaults write com.apple.dock autohide-time-modifier -float 0.15"
    nimo_panel_close
    nimo_blank

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "preview only, nothing was changed"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "Speed the dock up?"; then
        nimo_blank
        nimo_dim "left as it was"
        nimo_blank
        return 0
    fi

    nimo_look_log
    nimo_run defaults write com.apple.dock autohide -bool true
    nimo_run defaults write com.apple.dock autohide-delay -float 0
    nimo_run defaults write com.apple.dock autohide-time-modifier -float 0.15
    killall Dock >/dev/null 2>&1

    nimo_blank
    nimo_ok "The dock keeps up now."
    nimo_dim "back to the slow one with  min setup --restore"
    nimo_blank
    return 0
}

# The Windows counterpart: the row of pinned apps on the taskbar.
#
# A pin is two things at once — a shortcut in a folder, and a blob under
# Taskband that Explorer keeps in step with it. Removing one without the other
# leaves a pin that comes back, or a gap that does not fill. So the shortcut
# is moved aside, the blob is written down and cleared, and Explorer rebuilds
# the blob from the folder when it next starts.
#
# Nothing is uninstalled. Unpinning an app does not remove it, and it is one
# `min dock --restore` away from being back where it was.
nimo_dock_windows() {
    local pins count
    pins=$(nimo_win_pinned)
    count=$(nimo_line_count "$pins")

    nimo_panel_open "pinned to your taskbar"

    if [ "$count" -eq 0 ]; then
        nimo_dim "nothing is pinned to your taskbar"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    local labels="" paths="" name what
    while IFS=$'\t' read -r name what; do
        [ -n "${name:-}" ] || continue
        labels="$labels$name
"
        paths="$paths$what
"
        nimo_say "$name"
    done <<INNER
$pins
INNER

    nimo_blank
    nimo_rule
    nimo_total "Pinned" "$(nimo_plural "$count" app)"
    nimo_panel_close
    nimo_blank
    nimo_dim "unpinning does not uninstall anything, the app stays exactly"
    nimo_dim "where it is, and  min dock --restore  puts the pins back"
    nimo_blank

    if [ "${NIMO_LIST:-0}" = "1" ] || [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "run  min dock  to pick what goes"
        nimo_blank
        return 0
    fi

    local wanted
    if ! wanted=$(nimo_pick multi "↑↓ move   space tick what goes   a all   n none   enter confirm   q cancel" "$labels"); then
        nimo_dim "nothing was changed"
        nimo_blank
        return 0
    fi
    if [ -z "$wanted" ]; then
        nimo_dim "nothing ticked, your taskbar is as it was"
        nimo_blank
        return 0
    fi

    local n
    n=$(printf '%s' "$wanted" | wc -w | tr -d ' ')
    if ! nimo_confirm "Unpin $(nimo_plural "$n" app)?"; then
        nimo_blank
        nimo_dim "left as it was"
        nimo_blank
        return 0
    fi

    mkdir -p "$NIMO_UNDO_DIR" "$NIMO_BACKUP_DIR/taskbar" 2>/dev/null
    local log dest src gone=0 i
    log=$(nimo_free_file "$NIMO_UNDO_DIR/startup-$(date +%Y%m%d-%H%M%S)" .tsv)
    : > "$log"
    nimo_look_log
    printf 'prefs\t%s\t\n' "$NIMO_SETUP_LOG" >> "$log"

    # the blob first, so a failure here happens before anything moves
    nimo_win_record "$NIMO_WIN_TASKBAND" Favorites
    nimo_reg_erase "$NIMO_WIN_TASKBAND" Favorites

    for i in $wanted; do
        src=$(printf '%s' "$paths" | sed -n "${i}p")
        [ -n "$src" ] || continue
        [ -f "$src" ] || continue
        dest=$(nimo_free_name "$NIMO_BACKUP_DIR/taskbar" "$(basename "$src")")
        # Written down first: a machine that stops mid-move would otherwise
        # have unpinned the shortcut with nothing saying where it went.
        printf 'file\t%s\t%s\n' "$src" "$dest" >> "$log"
        if mv "$src" "$dest" 2>/dev/null; then
            gone=$((gone + 1))
        else
            nimo_undo_drop_last "$log"
        fi
    done

    nimo_blank
    nimo_ok "$(nimo_plural "$gone" app) unpinned"
    nimo_blank
    nimo_dim "the taskbar redraws when Explorer next starts"
    nimo_dim "changed your mind?  min dock --restore"
    nimo_blank
    return 0
}

# Take one named app out of the dock, for a caller that already knows which
# one: the window has its own list and its own question, and the picker below
# needs a terminal. The dock is exported first, the same as the picker does,
# so `min dock --restore` still puts back exactly what was there.
nimo_dock_drop_one() {
    local urls="$1" url name keep="" found="" used="" want hit

    # NIMO_ONLY is one name, or several with one on each line. Kliner's
    # starter takes a few apps out at once, and one backup before all of them
    # is what lets "put the dock back" bring every one of them back: one run
    # per app made a backup per app, and the newest held all but the last.
    # Each name takes out one icon, the first that answers to it.
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        name=$(nimo_dock_name "$url")
        hit=""
        while IFS= read -r want; do
            [ -n "$want" ] || continue
            case "$used" in
                *"
$want
"*) continue ;;
            esac
            if nimo_same_word "$name" "$want"; then
                hit="$want"
                break
            fi
        done <<WANT
$NIMO_ONLY
WANT
        if [ -n "$hit" ]; then
            used="$used
$hit
"
            found="${found:+$found, }$name"
            continue
        fi
        keep="$keep$url
"
    done <<INNER
$urls
INNER

    # every name that answered to nothing, said by its name
    while IFS= read -r want; do
        [ -n "$want" ] || continue
        case "$used" in
            *"
$want
"*) ;;
            *) nimo_warn "nimo cannot find \"$want\" in your dock" ;;
        esac
    done <<WANT
$NIMO_ONLY
WANT

    # NIMO_ADD: apps to put in, by name, one to a line, each found where
    # apps are installed and added after the ones that stay. Adding happens
    # in the same run as taking out, after the same one backup.
    local added="" path
    while IFS= read -r want; do
        [ -n "$want" ] || continue
        path=$(nimo_dock_installed | awk -F "$(printf '\t')" -v w="$want" 'tolower($1) == tolower(w) { print $2; exit }')
        if [ -z "$path" ]; then
            nimo_warn "nimo cannot find an app called \"$want\""
            continue
        fi
        # already in, and staying: there is nothing to add
        printf '%s' "$keep" | nimo_dock_holds "$path" && continue
        added="${added:+$added, }$(basename "$path" .app)"
        keep="$keep$(nimo_dock_url "$path")
"
    done <<WANT
${NIMO_ADD:-}
WANT

    if [ -z "$found" ] && [ -z "$added" ]; then
        nimo_blank
        return 1
    fi

    local question="Take $found out of your dock?"
    [ -z "$found" ] && question="Put $added in your dock?"
    [ -n "$found" ] && [ -n "$added" ] && question="Take $found out of your dock, and put $added in?"
    if ! nimo_confirm "$question"; then
        nimo_blank
        nimo_dim "your dock is exactly as it was"
        nimo_blank
        return 0
    fi

    local backup
    backup=$(nimo_dock_backup) || backup=""
    if [ -z "$backup" ]; then
        nimo_err "could not back up your dock, refusing to change it"
        nimo_blank
        return 1
    fi

    printf '%s' "$keep" | nimo_dock_rewrite

    nimo_blank
    [ -n "$found" ] && nimo_ok "Out of your dock: $found"
    [ -n "$added" ] && nimo_ok "Into your dock: $added"
    nimo_dim "the apps stay where they are, only the dock changes"
    nimo_dim "backup: $(basename "$backup")"
    nimo_blank
    return 0
}

# The slow dock back: the newest record of `min dock --fast`, replayed, and
# nothing else. `min setup --restore` puts back the newest preferences of any
# kind, which after a dark mode or a hidden menu bar is not the dock at all.
nimo_dock_fast_restore() {
    nimo_header
    local log="" f
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        if grep -q 'autohide-time-modifier' "$f" 2>/dev/null; then
            log="$f"
            break
        fi
    done <<EOF
$(ls -1t "$NIMO_BACKUP_DIR"/setup-*.tsv 2>/dev/null)
EOF
    if [ -z "$log" ]; then
        nimo_panel_open "a dock that keeps up"
        nimo_dim "nimo has not sped the dock up, nothing to put back"
        nimo_panel_close
        nimo_blank
        return 1
    fi
    NIMO_UNDO_QUIET=1 nimo_setup_restore "$log"
    killall Dock >/dev/null 2>&1
    nimo_undo_spend "$log"
    nimo_ok "The dock is back to how it was."
    nimo_blank
    return 0
}

nimo_cmd_dock() {
    if [ "${NIMO_FAST:-0}" = "1" ] && [ "${NIMO_RESTORE:-0}" = "1" ]; then
        nimo_dock_fast_restore
        return $?
    fi
    if [ "${NIMO_FAST:-0}" = "1" ]; then
        nimo_cmd_dock_fast
        return $?
    fi
    if [ "${NIMO_RESTORE:-0}" = "1" ]; then
        if [ "$(nimo_platform)" = "windows" ]; then
            nimo_startup_undo "" "put the pins back" "pinned again"
            return 0
        fi
        nimo_dock_restore
        return 0
    fi

    # --paths: every app in the dock as its name, a tab, and where the app
    # is, and nothing else. Kliner draws your Dock from this, icons and all;
    # the name is the one  --only  answers to.
    if [ "${NIMO_PATHS:-0}" = "1" ]; then
        nimo_is_macos || return 0
        local one
        # --all: the apps that are installed and not in it, the same way,
        # which is what Kliner offers to put in
        if [ "${NIMO_ALL:-0}" = "1" ]; then
            local held name path tab
            tab=$(printf '\t')
            held=$(nimo_dock_urls | while IFS= read -r one; do
                [ -n "$one" ] || continue
                nimo_dock_path "$one"
                echo
            done)
            nimo_dock_installed | while IFS="$tab" read -r name path; do
                [ -n "$path" ] || continue
                printf '%s\n' "$held" | grep -Fxq -- "$path" && continue
                printf '%s\t%s\n' "$name" "$path"
            done
            return 0
        fi
        while IFS= read -r one; do
            [ -n "$one" ] || continue
            printf '%s\t%s\n' "$(nimo_dock_name "$one")" "$(nimo_dock_path "$one")"
        done <<EOF
$(nimo_dock_urls)
EOF
        return 0
    fi

    nimo_header

    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_dock_windows
        return $?
    fi

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
        nimo_dim "nimo cannot read your dock, nothing was changed"
        nimo_panel_close
        nimo_blank
        return 1
    fi

    if [ -n "${NIMO_ONLY:-}" ] || [ -n "${NIMO_ADD:-}" ]; then
        nimo_panel_close
        nimo_blank
        nimo_dock_drop_one "$urls"
        return $?
    fi

    local labels="" i=1 url name hint
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        name=$(nimo_dock_name "$url")
        hint=""
        nimo_dock_is_stock "$name" && hint="came with macOS"
        labels="$labels$(printf '%-24s  %s' "$name" "$hint")
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
        nimo_dim "nothing ticked, your dock is exactly as it was"
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
        nimo_dim "those numbers matched nothing, your dock is as it was"
        nimo_blank
        return 0
    fi

    nimo_blank
    nimo_say "Leaving your dock:"
    printf '%s' "$drop" | while IFS= read -r name; do
        [ -n "$name" ] && nimo_dim "  $name"
    done
    nimo_blank
    nimo_dim "the apps stay installed, only the dock icons go"
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
        nimo_err "could not back up your dock, refusing to change it"
        nimo_blank
        return 1
    fi

    printf '%s' "$keep" | nimo_dock_rewrite

    nimo_blank
    nimo_ok "Dock rebuilt, $(nimo_plural "$dropped" app) fewer"
    nimo_dim "backup: $(basename "$backup")   ·   undo with  min dock --restore"
    nimo_blank
    return 0
}
