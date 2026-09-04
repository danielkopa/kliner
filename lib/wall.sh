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
    if [ "$(nimo_platform)" = "macos" ]; then
        # the store first: no Automation permission, no dialog, no -1743
        nimo_wall_store_read && return 0
    fi
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

# Setting it, and then checking that it happened.
#
# Apple has moved this three times: up to Ventura the Dock kept it in an
# sqlite database, Sonoma moved it to WallpaperAgent, and the AppleScript that
# used to work still **returns success on some of those systems while
# changing nothing at all**. So "osascript did not error" is not the same as
# "the wallpaper changed", and nimo used to print a tick either way — which is
# the worst thing a tool can do, because you then look for the fault in your
# own eyes.
#
# It reads the wallpaper back now. If it did not move, nimo says so.

# ---- the store, which needs nobody's permission -------------------------
#
# Since Sonoma the wallpaper lives in a plist in your own home folder, and
# WallpaperAgent reads it when it starts. That matters more than it sounds:
# every AppleScript route needs Automation permission, and a Mac that has once
# been told "Don't Allow" answers -1743 for ever and never asks again. Your own
# file in your own Library needs no permission at all.
#
# nimo edits it the careful way — read what is there, swap the image out, put
# it back — rather than writing a plist from scratch, because the shape of
# this file is Apple's and it changes.

nimo_wall_store() {
    printf '%s' "$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
}

# file:///System/Library/Desktop%20Pictures/Sky.heic
# Byte by byte under LC_ALL=C, so an accented name survives the trip.
nimo_url_encode() {
    LC_ALL=C awk -v s="$1" 'BEGIN {
        for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
        n = length(s); out = ""
        for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (c ~ /[A-Za-z0-9._~\/-]/) out = out c
            else out = out sprintf("%%%02X", ord[c])
        }
        printf "%s", out
    }'
}

# No strtonum here: that is a gawk extension, and the awk macOS ships is the
# one Kernighan wrote. Sixteen digits in a table is the portable answer.
nimo_url_decode() {
    LC_ALL=C awk -v s="$1" 'BEGIN {
        split("0 1 2 3 4 5 6 7 8 9", d, " ")
        for (i = 0; i <= 9; i++) hex[i "" ] = i
        hex["a"] = 10; hex["A"] = 10; hex["b"] = 11; hex["B"] = 11
        hex["c"] = 12; hex["C"] = 12; hex["d"] = 13; hex["D"] = 13
        hex["e"] = 14; hex["E"] = 14; hex["f"] = 15; hex["F"] = 15
        n = length(s); out = ""
        for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (c == "%" && i + 2 <= n) {
                hi = substr(s, i + 1, 1); lo = substr(s, i + 2, 1)
                if (hi in hex && lo in hex) {
                    out = out sprintf("%c", hex[hi] * 16 + hex[lo])
                    i = i + 2
                    continue
                }
            }
            out = out c
        }
        printf "%s", out
    }'
}

# What the store says is showing, as a plain path.
#
# Two ways of finding it, and the second is the reason this survives Apple:
# Sonoma put the path under a `relative` key, and a later macOS may not. So if
# that key is not there, nimo looks for any string that is a file:// URL
# ending in an image — which is what a wallpaper is, whatever the key around
# it happens to be called this year. A folder URL, or anything that is not an
# image, is left alone.
NIMO_WALL_IMAGE_RE='\\.([Hh][Ee][Ii][Cc]|[Jj][Pp][Ee]?[Gg]|[Pp][Nn][Gg]|[Tt][Ii][Ff][Ff]?)$'

nimo_wall_store_xml() {
    local store
    store=$(nimo_wall_store)
    [ -f "$store" ] || return 1
    nimo_have plutil || return 1
    plutil -convert xml1 -o - "$store" 2>/dev/null
}

nimo_wall_store_read() {
    local url
    url=$(nimo_wall_store_xml | awk -v img="$NIMO_WALL_IMAGE_RE" '
        /<key>relative<\/key>/ { want = 1; next }
        want && /<string>/ {
            line = $0
            sub(/.*<string>/, "", line); sub(/<\/string>.*/, "", line)
            if (line ~ /^file:\/\//) { print line; exit }
            want = 0
        }
        /<string>file:\/\// {
            line = $0
            sub(/.*<string>/, "", line); sub(/<\/string>.*/, "", line)
            if (line ~ img) { spare = spare == "" ? line : spare }
        }
        END { if (spare != "") print spare }') || return 1
    [ -n "$url" ] || return 1
    case "$url" in
        file://*) ;;
        *) return 1 ;;
    esac
    nimo_url_decode "${url#file://}"
}

# Swap the image, keeping every other thing the file says about your desktop.
nimo_wall_store_write() {
    local pic="$1" store xml url tmp
    store=$(nimo_wall_store)
    [ -f "$store" ] || return 1
    nimo_have plutil || return 1

    url="file://$(nimo_url_encode "$pic")"
    tmp="${TMPDIR:-/tmp}/nimo-wall.$$"
    plutil -convert xml1 -o "$tmp.xml" "$store" 2>/dev/null || { rm -f "$tmp.xml"; return 1; }

    # Two rules, and nothing else in the file is touched by either:
    #
    #   a string right after a <key>relative</key>   — Sonoma's shape
    #   any file:// string that names an image        — whatever Apple calls
    #                                                   the key this year
    #
    # A folder URL, or a string that is not an image, is left exactly as it
    # was. That is the difference between editing this file and rewriting it.
    awk -v url="$url" -v img="$NIMO_WALL_IMAGE_RE" '
        {
            hit = 0
            if (prev ~ /<key>relative<\/key>/ && /<string>/) hit = 1
            else if (/<string>file:\/\//) {
                line = $0
                sub(/.*<string>/, "", line); sub(/<\/string>.*/, "", line)
                if (line ~ img) hit = 1
            }
            if (hit) {
                i = index($0, "<string>")
                j = index($0, "</string>")
                if (i > 0 && j > i) {
                    was = $0
                    $0 = substr($0, 1, i + 7) url substr($0, j)
                    prev = was
                    print
                    next
                }
            }
            print; prev = $0
        }
    ' "$tmp.xml" > "$tmp.new" 2>/dev/null || { rm -f "$tmp.xml" "$tmp.new"; return 1; }

    grep -q -- "$url" "$tmp.new" || { rm -f "$tmp.xml" "$tmp.new"; return 1; }

    # The one it had before nimo ever touched the file, kept whole.
    mkdir -p "$NIMO_BACKUP_DIR" 2>/dev/null
    [ -f "$NIMO_BACKUP_DIR/wallpaper-store.plist" ] || \
        cp "$store" "$NIMO_BACKUP_DIR/wallpaper-store.plist" 2>/dev/null

    plutil -convert binary1 -o "$store" "$tmp.new" 2>/dev/null || {
        rm -f "$tmp.xml" "$tmp.new"; return 1; }
    rm -f "$tmp.xml" "$tmp.new"

    # It reads the store when it starts, and comes straight back by itself.
    killall WallpaperAgent >/dev/null 2>&1
    return 0
}

NIMO_WALL_METHOD=""   # the one that worked here, once we know
NIMO_WALL_WHY=""      # what the system said, when nothing worked
NIMO_WALL_UNSURE=0    # it was told to; nimo could not check that it did

# Did it actually take? Empty means nimo cannot read the wallpaper at all,
# which is a different problem and gets a different sentence.
nimo_wall_took() {
    local want="$1" now
    sleep 0.4 2>/dev/null || sleep 1
    now=$(nimo_wall_current 2>/dev/null) || now=""
    [ -n "$now" ] || return 2
    [ "$now" = "$want" ]
}

nimo_wall_osa() {
    NIMO_WALL_WHY=$(osascript -e "$1" 2>&1)
    [ -z "$NIMO_WALL_WHY" ]
}

nimo_wall_apply() {
    local pic="$1" verdict

    if [ "$(nimo_platform)" = "windows" ]; then
        # The value is a path Windows has to be able to read, so it goes in
        # backslashed. Then the documented poke, which is the whole of it —
        # nimo does not kill Explorer to make a wallpaper take.
        nimo_win_set "$NIMO_WIN_DESKTOP" WallPaper REG_SZ "$(nimo_win_path "$pic")"
        nimo_win_refresh
        return 0
    fi

    # Once one of them is known to work on this machine, the rest of the
    # session uses it directly — flipping through forty wallpapers should not
    # re-run the whole audition each time.
    case "$NIMO_WALL_METHOD" in
        store)  nimo_wall_store_write "$pic"; return 0 ;;
        events) nimo_wall_osa "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$pic\""; return 0 ;;
        finder) nimo_wall_osa "tell application \"Finder\" to set desktop picture to POSIX file \"$pic\""; return 0 ;;
        agent)
            nimo_wall_osa "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$pic\""
            killall WallpaperAgent >/dev/null 2>&1
            return 0 ;;
        dock)
            sqlite3 "$HOME/Library/Application Support/Dock/desktoppicture.db" \
                "update data set value = '$pic'" >/dev/null 2>&1
            killall Dock >/dev/null 2>&1
            return 0 ;;
    esac

    # The store first. It is the only way that asks nobody for anything.
    if nimo_wall_store_write "$pic"; then
        if nimo_wall_took "$pic"; then NIMO_WALL_METHOD=store; return 0; fi
    fi

    nimo_wall_osa "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$pic\""
    nimo_wall_took "$pic"; verdict=$?
    if [ "$verdict" = "0" ]; then NIMO_WALL_METHOD=events; return 0; fi

    # 2 means nimo cannot read the wallpaper back at all. It can still try the
    # rest — a Mac that refuses to answer questions may still take orders —
    # but it cannot claim any of it worked, so it says that instead of a tick.
    if [ "$verdict" = "2" ]; then
        NIMO_WALL_UNSURE=1
        nimo_wall_osa "tell application \"Finder\" to set desktop picture to POSIX file \"$pic\""
        killall WallpaperAgent >/dev/null 2>&1
        if nimo_have sqlite3; then
            local blind="$HOME/Library/Application Support/Dock/desktoppicture.db"
            if [ -f "$blind" ] && sqlite3 "$blind" "update data set value = '$pic'" >/dev/null 2>&1; then
                killall Dock >/dev/null 2>&1
                return 0
            fi
        fi
        return 2
    fi

    nimo_wall_osa "tell application \"Finder\" to set desktop picture to POSIX file \"$pic\""
    if nimo_wall_took "$pic"; then NIMO_WALL_METHOD=finder; return 0; fi

    # Written, but not redrawn: since Sonoma the screen belongs to
    # WallpaperAgent, and it reads the setting when it starts.
    killall WallpaperAgent >/dev/null 2>&1
    if nimo_wall_took "$pic"; then NIMO_WALL_METHOD=agent; return 0; fi

    if nimo_have sqlite3; then
        local db="$HOME/Library/Application Support/Dock/desktoppicture.db"
        if [ -f "$db" ] && sqlite3 "$db" "update data set value = '$pic'" >/dev/null 2>&1; then
            killall Dock >/dev/null 2>&1
            if nimo_wall_took "$pic"; then NIMO_WALL_METHOD=dock; return 0; fi
        fi
    fi
    return 1
}

# Told, but not checked. Said out loud, because a tick nimo cannot stand
# behind is worse than no tick: you go looking for the fault in your own eyes.
nimo_wall_unsure_note() {
    [ "${NIMO_WALL_UNSURE:-0}" = "1" ] || return 0
    nimo_blank
    nimo_dim "nimo could not read the wallpaper back, so it cannot promise that took"
    nimo_dim "if the screen did not change, allow your terminal to control"
    nimo_dim "System Events in  Settings › Privacy & Security › Automation"
}

# The sentence to print when it did not work, which depends on why.
nimo_wall_complain() {
    local why="${NIMO_WALL_WHY:-}" store
    store=$(nimo_wall_store)

    if [ "${1:-1}" = "2" ]; then
        nimo_warn "nimo cannot read your wallpaper, so it cannot set one either"
        nimo_blank
        nimo_dim "that is almost always one permission:"
        nimo_dim "System Settings › Privacy & Security › Automation"
        nimo_dim "find your terminal in the list and allow System Events and Finder"
        return 0
    fi

    # -1743 is errAEEventNotPermitted: the Automation permission was refused
    # once, and macOS remembers that answer for ever without ever asking
    # again. The toggle is often not even in Settings, because a permission
    # that was never granted has nothing to show.
    case "$why" in
        *-1743*|*"Not authorised"*|*"Not authorized"*)
            nimo_warn "your Mac will not let this terminal control the desktop"
            nimo_dim "it said: $why"
            nimo_blank
            nimo_dim "macOS asks once and remembers the answer for ever. to be"
            nimo_dim "asked again, run this and then try nimo once more:"
            nimo_blank
            nimo_dim "    tccutil reset AppleEvents"
            nimo_blank
            nimo_dim "say yes when the box appears. nothing else on your Mac loses"
            nimo_dim "anything by it, it only forgets the answers."
            ;;
        *)
            nimo_warn "nimo asked your Mac to change the wallpaper and it did not"
            [ -n "$why" ] && nimo_dim "it said: $why"
            nimo_blank
            nimo_dim "run  bash tools/wallcheck.sh  in the nimo folder"
            nimo_dim "and send what it prints"
            ;;
    esac

    # The way that needs no permission would have covered this, if nimo knew
    # the shape of the file. Apple changes it, and guessing at the shape of a
    # file nimo is about to write is the one thing it must not do.
    if [ -f "$store" ] && ! nimo_wall_store_read >/dev/null 2>&1; then
        nimo_blank
        nimo_dim "your Mac keeps the wallpaper in a file nimo does not recognise"
        nimo_dim "the shape of. show it what is in there:"
        nimo_dim "    bash tools/wallstore.sh"
    fi
    return 0
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
        nimo_wall_unsure_note
    else
        nimo_wall_complain "$?"
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
        printf "  %s%-$((NIMO_PANEL_WIDTH - 18))s%s %s%s of %s%s\033[K\n" \
            "$NIMO_C_BOLD" "$(nimo_wall_pretty "$here")" "$NIMO_C_RESET" \
            "$NIMO_C_DIM" "$at" "$count" "$NIMO_C_RESET" >&2
        printf '\n' >&2
        if [ "${NIMO_COLS:-80}" -lt 52 ]; then
            printf '  %sn p  flip   enter  keep   q  back%s\033[K\n' \
                "$NIMO_C_DIM" "$NIMO_C_RESET" >&2
        elif [ "${NIMO_COLS:-80}" -lt 72 ]; then
            printf '  %sn p  flip    r  random    enter  keep    q  back%s\033[K\n' \
                "$NIMO_C_DIM" "$NIMO_C_RESET" >&2
        else
            printf '  %s↑↓ or n p  flip     r  random     enter  keep it     q  put it back%s\033[K\n' \
                "$NIMO_C_DIM" "$NIMO_C_RESET" >&2
        fi
        printf '  %sit changes on your screen as you move%s\033[K\n' \
            "$NIMO_C_DIM" "$NIMO_C_RESET" >&2
        drawn=1
    }

    # If the first one does not take, everything after it is a menu that
    # changes nothing — better to stop here and say why.
    nimo_wall_apply "$here" >/dev/null 2>&1 || {
        printf '\033[?25h' >&2
        NIMO_WALL_FAILED=$?
        return 2
    }
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

# Two ways back, tried in that order for a reason.
#
# Setting the wallpaper you had is the surgical one: it leaves alone anything
# else you have changed since. Putting the whole store file back is the exact
# one, and it is what is left when the surgical way cannot work — the picture
# has been deleted, or your Mac will not take orders. nimo keeps both, so it
# has an answer either way.
# Spent, not destroyed. This was the one place in nimo that deleted its own
# record of what it had done, which is the thing nimo says it never does, and
# it took the whole-store backup with it — so after one restore there was no
# trace nimo had ever touched the wallpaper.
nimo_wall_forget() {
    local kept
    for kept in "$NIMO_BACKUP_DIR/wallpaper.txt" \
                "$NIMO_BACKUP_DIR/$NIMO_WALL_AT" \
                "$NIMO_BACKUP_DIR/wallpaper-store.plist"; do
        [ -e "$kept" ] || continue
        nimo_undo_spend "$kept"
    done
}

nimo_wall_restore() {
    nimo_header
    nimo_panel_open "put the wallpaper back"

    local saved="$NIMO_BACKUP_DIR/wallpaper.txt" kept was store
    kept="$NIMO_BACKUP_DIR/wallpaper-store.plist"
    store=$(nimo_wall_store)

    if [ ! -f "$saved" ] && [ ! -f "$kept" ]; then
        nimo_dim "no wallpaper saved yet, nimo has not changed it"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    was=$(cat "$saved" 2>/dev/null)
    if [ -n "$was" ] && [ -f "$was" ] && nimo_wall_apply "$was"; then
        # armed again: the next change is a fresh "before" to come back to,
        # and the flipping starts from where you actually are
        nimo_wall_forget
        nimo_ok "Wallpaper restored"
        nimo_dim "$(nimo_wall_pretty "$was")"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    if [ -f "$kept" ] && [ -f "$store" ] && cp "$kept" "$store" 2>/dev/null; then
        killall WallpaperAgent >/dev/null 2>&1
        nimo_wall_forget
        nimo_ok "Wallpaper restored"
        if [ -n "$was" ] && [ ! -f "$was" ]; then
            nimo_dim "the picture you had is gone, so nimo put back the whole"
            nimo_dim "setting instead, exactly as it was before it started"
        else
            nimo_dim "put back from the copy nimo kept of the setting itself"
        fi
        nimo_panel_close
        nimo_blank
        return 0
    fi

    nimo_warn "could not put it back"
    nimo_dim "it was: ${was:-unknown}"
    [ -n "$was" ] && [ ! -f "$was" ] && nimo_dim "and that file is not there any more"
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
        [ "$count" -gt "$limit" ] && nimo_dim "$((count - limit)) more, see them all with  min wallpaper --limit $count"
        nimo_blank
        nimo_dim "run  min wallpaper  to choose one"
        nimo_blank
        return 0
    fi

    # The panel above is a list; from here on nimo is doing something, and
    # a box left open runs the result into it.
    [ "$browse" = "1" ] || nimo_panel_close

    local chosen=""
    if [ "${NIMO_RANDOM:-0}" = "1" ]; then
        chosen=$(printf '%s\n' "$list" | awk 'BEGIN{srand()} {a[NR]=$0} END{print a[int(rand()*NR)+1]}')
    elif [ "${NIMO_ASSUME_YES:-0}" = "1" ]; then
        chosen="$suggested"
    elif [ "$browse" = "1" ]; then
        # A list of names tells you nothing about a wallpaper. This puts each
        # one on your own screen as you move through them, and puts back the
        # one you had if you change your mind.
        chosen=$(nimo_wall_browse "$list" "$count")
        case "$?" in
            2)
                nimo_blank
                nimo_wall_complain 1
                nimo_blank
                return 1 ;;
        esac
        if [ -z "$chosen" ]; then
            nimo_blank
            nimo_dim "put back the one you had"
            nimo_blank
            return 0
        fi
        nimo_blank
        nimo_ok "Kept, $(nimo_wall_pretty "$chosen")"
        nimo_dim "the one you had before is one  min wallpaper --restore  away"
        nimo_blank
        return 0
    elif [ -t 0 ]; then
        printf '  Which one? (number, enter for nimo'\''s pick): '
        local answer=""
        read -r answer || answer=""
        case "$answer" in
            '')          chosen="$suggested" ;;
            *[!0-9]*)    nimo_blank; nimo_dim "that was not a number, nothing changed"; nimo_blank; return 0 ;;
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
        nimo_dim "no such wallpaper, nothing changed"
        nimo_blank
        return 0
    fi

    nimo_wall_keep_original

    nimo_blank
    if nimo_wall_apply "$chosen"; then
        nimo_wall_remember "$chosen"
        nimo_ok "Wallpaper set, $(nimo_wall_pretty "$chosen")"
        nimo_dim "flip on with  min next   ·   undo with  min wallpaper --restore"
        nimo_wall_unsure_note
    else
        nimo_wall_complain "$?"
    fi
    nimo_blank
    return 0
}
