#!/usr/bin/env bash
# nimo :: lib/wall.sh — a calmer wallpaper, from the ones you already have.
#
# Nothing is downloaded. nimo only offers files that are already on the machine
# — macOS's Desktop Pictures, or the folders under C:\Windows\Web — writes down
# what you had before, and can put it back.

nimo_wall_dirs() {
    if [ "$(nimo_platform)" = "windows" ]; then
        # Windows keeps its own under Web: one folder per theme, plus the 4K
        # set and the lock screen pictures. Listing the folders rather than
        # naming them means a theme nimo has never heard of still turns up.
        local web
        web="$(nimo_win_dir)/Web"
        [ -d "$web" ] && find "$web" -maxdepth 2 -type d 2>/dev/null
        return 0
    fi
    printf '%s\n' \
        "/System/Library/Desktop Pictures" \
        "/System/Library/Desktop Pictures/Solid Colors" \
        "/Library/Desktop Pictures" \
        "$HOME/Library/Application Support/com.apple.mobileAssetDesktop"
}

nimo_wall_list() {
    local dir
    while IFS= read -r dir; do
        [ -d "$dir" ] || continue
        find "$dir" -maxdepth 1 -type f \
            \( -name '*.heic' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' \) \
            2>/dev/null
    done <<EOF
$(nimo_wall_dirs)
EOF
}

nimo_wall_pretty() {
    local n
    n=$(basename "$1")
    n="${n%.*}"
    printf '%s' "$n"
}

nimo_wall_current() {
    if [ "$(nimo_platform)" = "windows" ]; then
        local raw
        raw=$(nimo_reg_read "$NIMO_WIN_DESKTOP" WallPaper 2>/dev/null) || return 1
        [ -n "$raw" ] || return 1
        if nimo_have cygpath; then
            cygpath -u "$raw" 2>/dev/null && return 0
        fi
        printf '%s' "$raw" | tr '\\\\' '/'
        return 0
    fi
    osascript -e 'tell application "Finder" to get POSIX path of (get desktop picture as alias)' 2>/dev/null
}

# Three ways to set it, because Apple keeps moving this one.
nimo_wall_apply() {
    local pic="$1"

    if [ "$(nimo_platform)" = "windows" ]; then
        # The value is a path Windows has to be able to read, so it goes in
        # backslashed. Then the documented poke, which is the whole of it —
        # nimo does not kill Explorer to make a wallpaper take.
        nimo_win_set "$NIMO_WIN_DESKTOP" WallPaper REG_SZ "$(nimo_win_path "$pic")"
        nimo_win_refresh
        return 0
    fi

    if osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$pic\"" >/dev/null 2>&1; then
        return 0
    fi
    if osascript -e "tell application \"Finder\" to set desktop picture to POSIX file \"$pic\"" >/dev/null 2>&1; then
        return 0
    fi
    if nimo_have sqlite3; then
        local db="$HOME/Library/Application Support/Dock/desktoppicture.db"
        if [ -f "$db" ] && sqlite3 "$db" "update data set value = '$pic'" >/dev/null 2>&1; then
            killall Dock >/dev/null 2>&1
            return 0
        fi
    fi
    return 1
}

# nimo's own taste: the plainest thing available.
nimo_wall_suggest() {
    local list="$1" pick
    if [ "$(nimo_platform)" = "windows" ]; then
        pick=$(printf '%s\n' "$list" | grep -i '/Wallpaper/Windows/' | head -1)
        [ -n "$pick" ] || pick=$(printf '%s\n' "$list" | grep -i '/Web/Wallpaper/' | head -1)
        [ -n "$pick" ] || pick=$(printf '%s\n' "$list" | head -1)
        printf '%s' "$pick"
        return 0
    fi
    pick=$(printf '%s\n' "$list" | grep -i '/Solid Colors/' | head -1)
    [ -n "$pick" ] || pick=$(printf '%s\n' "$list" | grep -i 'gradient' | head -1)
    [ -n "$pick" ] || pick=$(printf '%s\n' "$list" | grep -i 'monterey\|ventura\|sonoma\|sequoia' | head -1)
    [ -n "$pick" ] || pick=$(printf '%s\n' "$list" | head -1)
    printf '%s' "$pick"
}

nimo_wall_restore() {
    nimo_header
    nimo_panel_open "put the wallpaper back"

    local saved="$NIMO_BACKUP_DIR/wallpaper.txt" was
    if [ ! -f "$saved" ]; then
        nimo_dim "no wallpaper saved yet — nimo has not changed it"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    was=$(cat "$saved" 2>/dev/null)
    if [ -n "$was" ] && [ -f "$was" ] && nimo_wall_apply "$was"; then
        nimo_ok "Wallpaper restored"
        nimo_dim "$(nimo_wall_pretty "$was")"
    else
        nimo_warn "could not put it back"
        nimo_dim "it was: ${was:-unknown}"
    fi

    nimo_panel_close
    nimo_blank
    return 0
}

nimo_cmd_wallpaper() {
    if [ "${NIMO_RESTORE:-0}" = "1" ]; then
        nimo_wall_restore
        return 0
    fi

    nimo_header

    case "$(nimo_platform)" in
        macos|windows) ;;
        *)
            nimo_warn "min wallpaper knows macOS and Windows, not this"
            nimo_blank
            return 0 ;;
    esac

    local list count where
    list=$(nimo_wall_list | sort)
    count=$(nimo_line_count "$list")

    if [ "$(nimo_platform)" = "windows" ]; then
        where="wallpapers on this pc"
    else
        where="wallpapers on this mac"
    fi
    nimo_panel_open "$where"

    if [ "$count" -eq 0 ]; then
        nimo_dim "nimo could not find any of the wallpapers your system ships with"
        nimo_panel_close
        nimo_blank
        nimo_dim "nothing was changed"
        nimo_blank
        return 1
    fi

    local suggested
    suggested=$(nimo_wall_suggest "$list")

    local labels="" pic hint limit="${NIMO_LIMIT:-15}" i=1
    while IFS= read -r pic; do
        [ -n "$pic" ] || continue
        [ "$i" -gt "$limit" ] && break
        hint=""
        [ "$pic" = "$suggested" ] && hint="nimo would pick this one"
        labels="$labels$(printf '%-30s %s' "$(nimo_wall_pretty "$pic")" "$hint")
"
        i=$((i + 1))
    done <<EOF
$list
EOF

    if [ "${NIMO_LIST:-0}" = "1" ] || [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        i=1
        while IFS= read -r hint; do
            [ -n "$hint" ] || continue
            printf '%s%s%2d%s  %s\n' "$NIMO_PAD" "$NIMO_C_DIM" "$i" "$NIMO_C_RESET" "$hint"
            i=$((i + 1))
        done <<EOF
$labels
EOF
        nimo_panel_close
        [ "$count" -gt "$limit" ] && nimo_dim "$((count - limit)) more — see them all with  min wallpaper --limit $count"
        nimo_blank
        nimo_dim "run  min wallpaper  to choose one"
        nimo_blank
        return 0
    fi

    local chosen=""
    if [ "${NIMO_RANDOM:-0}" = "1" ]; then
        chosen=$(printf '%s\n' "$list" | awk 'BEGIN{srand()} {a[NR]=$0} END{print a[int(rand()*NR)+1]}')
    elif [ "${NIMO_ASSUME_YES:-0}" = "1" ]; then
        chosen="$suggested"
    elif [ -t 0 ]; then
        printf '  Which one? (number, enter for nimo'\''s pick): '
        local answer=""
        read -r answer || answer=""
        case "$answer" in
            '')          chosen="$suggested" ;;
            *[!0-9]*)    nimo_blank; nimo_dim "that was not a number — nothing changed"; nimo_blank; return 0 ;;
            *)           chosen=$(printf '%s\n' "$list" | sed -n "${answer}p") ;;
        esac
    else
        nimo_dim "run this in a terminal to choose one"
        nimo_blank
        return 0
    fi

    if [ -z "$chosen" ] || [ ! -f "$chosen" ]; then
        nimo_blank
        nimo_dim "no such wallpaper — nothing changed"
        nimo_blank
        return 0
    fi

    mkdir -p "$NIMO_BACKUP_DIR" 2>/dev/null
    local before
    before=$(nimo_wall_current)
    [ -n "$before" ] && printf '%s\n' "$before" > "$NIMO_BACKUP_DIR/wallpaper.txt"

    nimo_blank
    if nimo_wall_apply "$chosen"; then
        nimo_ok "Wallpaper set — $(nimo_wall_pretty "$chosen")"
        [ -n "$before" ] && nimo_dim "undo with  min wallpaper --restore"
    else
        nimo_warn "macOS would not let nimo set the wallpaper"
        nimo_dim "System Settings → Wallpaper, or give your terminal Automation access"
    fi
    nimo_blank
    return 0
}
