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

# ---- flipping through them --------------------------------------------
#
# The list is not the point. Seeing it on your own screen is. So stepping
# applies each one as you move, and `q` puts back the one you started with —
# which means nimo has to remember two different things: the wallpaper you had
# before it ever touched anything, and the one it is showing you right now.

NIMO_WALL_AT="wallpaper-at.txt"

# Where the flipping is up to. The path, not a number: a list that grows or
# shrinks between runs would make a number point at something else.
nimo_wall_at() {
    local at="$NIMO_BACKUP_DIR/$NIMO_WALL_AT"
    if [ -f "$at" ]; then
        cat "$at" 2>/dev/null
        return 0
    fi
    nimo_wall_current 2>/dev/null
}

nimo_wall_remember() {
    mkdir -p "$NIMO_BACKUP_DIR" 2>/dev/null
    printf '%s\n' "$1" > "$NIMO_BACKUP_DIR/$NIMO_WALL_AT"
}

# The wallpaper you had before nimo ever changed it. Written once and left
# alone while you flip, or `q` would put back the one you saw a second ago.
nimo_wall_keep_original() {
    local saved="$NIMO_BACKUP_DIR/wallpaper.txt" before
    [ -f "$saved" ] && return 0
    before=$(nimo_wall_current 2>/dev/null) || before=""
    [ -n "$before" ] || return 0
    mkdir -p "$NIMO_BACKUP_DIR" 2>/dev/null
    printf '%s\n' "$before" > "$saved"
}

# One step through the list, wrapping at both ends.
#
#   $1  the list      $2  where we are now      $3  +1 or -1
nimo_wall_neighbour() {
    local list="$1" here="$2" step="$3"
    printf '%s\n' "$list" | awk -v here="$here" -v step="$step" '
        { a[NR] = $0; if ($0 == here) at = NR }
        END {
            if (NR == 0) exit 1
            if (at == 0) at = 1
            n = at + step
            if (n > NR) n = 1
            if (n < 1)  n = NR
            print a[n]
        }'
}

nimo_wall_where() {
    printf '%s\n' "$1" | awk -v here="$2" '$0 == here { print NR; found = 1 } END { if (!found) print 0 }'
}

# min next / min prev: one step, applied, and a line saying which one.
nimo_wall_step() {
    local step="$1" list count here nextone at

    nimo_header

    case "$(nimo_platform)" in
        macos|windows) ;;
        *)
            nimo_warn "wallpapers are a macOS and Windows thing"
            nimo_blank
            return 0 ;;
    esac

    list=$(nimo_wall_list | sort)
    count=$(nimo_line_count "$list")
    if [ "$count" -eq 0 ]; then
        nimo_warn "nimo could not find any of the wallpapers your system ships with"
        nimo_blank
        return 1
    fi

    here=$(nimo_wall_at)
    nextone=$(nimo_wall_neighbour "$list" "$here" "$step") || nextone=""
    if [ -z "$nextone" ]; then
        nimo_warn "nimo lost its place in the list"
        nimo_blank
        return 1
    fi

    nimo_wall_keep_original

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "would set  $(nimo_wall_pretty "$nextone")"
        nimo_blank
        return 0
    fi

    if nimo_wall_apply "$nextone"; then
        nimo_wall_remember "$nextone"
        at=$(nimo_wall_where "$list" "$nextone")
        nimo_ok "$(nimo_wall_pretty "$nextone")"
        nimo_dim "$at of $count   ·   min next   min prev   min wallpaper --restore"
    else
        nimo_warn "your system would not let nimo set the wallpaper"
        nimo_dim "give your terminal Automation access, or set it in System Settings"
    fi
    nimo_blank
    return 0
}

nimo_cmd_next() { nimo_wall_step 1; }
nimo_cmd_prev() { nimo_wall_step -1; }

# The live flip-through: every move puts it on your screen.
#
# Everything it draws goes to stderr, and it redraws by moving up and back
# down — relative moves only, because `\033[u` is not the same escape on every
# terminal and the last thing this should do is print itself over its own
# panel.
nimo_wall_browse() {
    local list="$1" count="$2" here at pic key drawn=0 rows=5
    local started

    started=$(nimo_wall_current 2>/dev/null) || started=""
    here=$(nimo_wall_at)
    [ -n "$here" ] || here=$(printf '%s\n' "$list" | head -1)
    at=$(nimo_wall_where "$list" "$here")
    [ "${at:-0}" -gt 0 ] || { here=$(printf '%s\n' "$list" | head -1); at=1; }

    nimo_wall_keep_original

    printf '\033[?25l' >&2
    trap 'printf "\033[?25h" >&2' EXIT INT TERM

    nimo_wall_draw() {
        [ "$drawn" -eq 1 ] && printf '\033[%dA' "$rows" >&2
        printf '\n' >&2
        printf '  %s%-34s%s %s%s of %s%s\033[K\n' \
            "$NIMO_C_BOLD" "$(nimo_wall_pretty "$here")" "$NIMO_C_RESET" \
            "$NIMO_C_DIM" "$at" "$count" "$NIMO_C_RESET" >&2
        printf '\n' >&2
        printf '  %s↑↓ or n p  flip     r  random     enter  keep it     q  put it back%s\033[K\n' \
            "$NIMO_C_DIM" "$NIMO_C_RESET" >&2
        printf '  %sit changes on your screen as you move%s\033[K\n' \
            "$NIMO_C_DIM" "$NIMO_C_RESET" >&2
        drawn=1
    }

    nimo_wall_apply "$here" >/dev/null 2>&1
    nimo_wall_draw

    while :; do
        key=$(nimo_read_key) || key=quit
        case "$key" in
            # n is "none" to the picker and "next" here — the same key, read
            # by whoever is asking
            down|right|none) pic=$(nimo_wall_neighbour "$list" "$here" 1) ;;
            up|left|prev)    pic=$(nimo_wall_neighbour "$list" "$here" -1) ;;
            random)          pic=$(printf '%s\n' "$list" | awk 'BEGIN{srand()} {a[NR]=$0} END{print a[int(rand()*NR)+1]}') ;;
            *)               pic="" ;;
        esac
        case "$key" in
            enter)
                printf '\033[?25h' >&2
                nimo_wall_remember "$here"
                printf '%s' "$here"
                return 0 ;;
            quit|escape)
                printf '\033[?25h' >&2
                [ -n "$started" ] && nimo_wall_apply "$started" >/dev/null 2>&1
                return 1 ;;
        esac
        [ -n "$pic" ] || continue
        here="$pic"
        at=$(nimo_wall_where "$list" "$here")
        nimo_wall_apply "$here" >/dev/null 2>&1
        nimo_wall_draw
    done
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
        # armed again: the next change is a fresh "before" to come back to,
        # and the flipping starts from where you actually are
        rm -f "$saved" "$NIMO_BACKUP_DIR/$NIMO_WALL_AT" 2>/dev/null
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

    local list count where browse=0
    list=$(nimo_wall_list | sort)
    count=$(nimo_line_count "$list")

    # Decided before anything is drawn: the browser puts its own thing on the
    # screen, and opening a panel it never fills leaves an empty box above it.
    if [ "${NIMO_RANDOM:-0}" != "1" ] && [ "${NIMO_ASSUME_YES:-0}" != "1" ] \
       && [ "${NIMO_LIST:-0}" != "1" ] && [ "${NIMO_DRY_RUN:-0}" != "1" ] \
       && [ "$count" -gt 0 ] && nimo_pick_capable; then
        browse=1
    fi

    if [ "$(nimo_platform)" = "windows" ]; then
        where="wallpapers on this pc"
    else
        where="wallpapers on this mac"
    fi
    [ "$browse" = "1" ] || nimo_panel_open "$where"

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
    elif [ "$browse" = "1" ]; then
        # A list of names tells you nothing about a wallpaper. This puts each
        # one on your own screen as you move through them, and puts back the
        # one you had if you change your mind.
        if ! chosen=$(nimo_wall_browse "$list" "$count") || [ -z "$chosen" ]; then
            nimo_blank
            nimo_dim "put back the one you had"
            nimo_blank
            return 0
        fi
        nimo_blank
        nimo_ok "Kept — $(nimo_wall_pretty "$chosen")"
        nimo_dim "the one you had before is one  min wallpaper --restore  away"
        nimo_blank
        return 0
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
        nimo_dim "run this in a terminal to flip through them"
        nimo_blank
        nimo_dim "or step one at a time:  min next   min prev"
        nimo_blank
        return 0
    fi

    if [ -z "$chosen" ] || [ ! -f "$chosen" ]; then
        nimo_blank
        nimo_dim "no such wallpaper — nothing changed"
        nimo_blank
        return 0
    fi

    nimo_wall_keep_original

    nimo_blank
    if nimo_wall_apply "$chosen"; then
        nimo_wall_remember "$chosen"
        nimo_ok "Wallpaper set — $(nimo_wall_pretty "$chosen")"
        nimo_dim "flip on with  min next   ·   undo with  min wallpaper --restore"
    else
        nimo_warn "macOS would not let nimo set the wallpaper"
        nimo_dim "System Settings → Wallpaper, or give your terminal Automation access"
    fi
    nimo_blank
    return 0
}
