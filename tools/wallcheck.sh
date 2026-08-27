#!/usr/bin/env bash
#
#   bash tools/wallcheck.sh
#
# Which way of setting the wallpaper actually works on this Mac?
#
# Apple has moved this three times. Up to Ventura the Dock kept it in an
# sqlite database; Sonoma moved it to WallpaperAgent and a plist nobody should
# be writing by hand; the AppleScript that used to work still returns success
# on some of those systems while changing nothing at all.
#
# So this asks the machine rather than guessing: it reads the wallpaper, tries
# each method, and reads it back to see whether anything moved. It puts your
# own wallpaper back at the end.
set -u

say()  { printf '  %s\n' "$*"; }
step() { printf '\n  \033[1m%s\033[0m\n' "$*"; }

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
STORE="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"

# nimo's own reader and writer, so this checks the thing that will actually
# run rather than an imitation of it
. "$ROOT/lib/ui.sh"
. "$ROOT/lib/core.sh"
. "$ROOT/lib/win.sh"
. "$ROOT/lib/wall.sh"

current() {
    nimo_wall_store_read 2>/dev/null && return 0
    osascript -e 'tell application "Finder" to get POSIX path of (get desktop picture as alias)' 2>/dev/null
}

printf '\n  \033[1mnimo — which wallpaper method works here\033[0m\n\n'
say "macOS   $(sw_vers -productVersion 2>/dev/null) ($(uname -m))"

BEFORE=$(current)
if [ -z "$BEFORE" ]; then
    say "reading the current wallpaper: FAILED"
    say "  → that is usually Automation permission, not the wallpaper itself"
    say "  → System Settings › Privacy & Security › Automation › your terminal"
else
    say "now     $BEFORE"
fi

# two candidates that are not the current one
LIST=$(find "/System/Library/Desktop Pictures" "$HOME/Library/Application Support/com.apple.mobileAssetDesktop" \
        -maxdepth 1 -type f \( -name '*.heic' -o -name '*.jpg' -o -name '*.png' \) 2>/dev/null | sort)
TRY=$(printf '%s\n' "$LIST" | grep -v -F -x "${BEFORE:-/nothing}" | head -1)

if [ -z "$TRY" ]; then
    say ""
    say "no wallpapers found to try — nimo looked in:"
    say "  /System/Library/Desktop Pictures"
    say "  ~/Library/Application Support/com.apple.mobileAssetDesktop"
    exit 1
fi
say "trying  $TRY"

took() {
    sleep 1
    local now
    now=$(current)
    if [ -n "$now" ] && [ "$now" = "$TRY" ]; then
        printf '    \033[32mWORKED\033[0m  — and the screen should have changed\n'
        return 0
    fi
    printf '    did not take (still %s)\n' "${now:-unreadable}"
    return 1
}

WORKED=""

step "0. the store in your own Library — needs no permission"
if [ -f "$STORE" ]; then
    say "    found: $STORE"
    say "    it says: $(nimo_wall_store_read 2>/dev/null || echo 'could not read it')"
    if nimo_wall_store_write "$TRY" 2>/dev/null; then
        say "    written, and WallpaperAgent restarted"
        took && WORKED="${WORKED}0 "
    else
        say "    nimo could not write it — the shape of the file is not what it expects"
    fi
else
    say "    no such file on this macOS"
    say "    what is there:"
    ls -la "$HOME/Library/Application Support/com.apple.wallpaper" 2>/dev/null | sed 's/^/      /' || say "      nothing at all"
fi

step "1. System Events, every desktop"
ERR=$(osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$TRY\"" 2>&1)
[ -n "$ERR" ] && say "    said: $ERR"
took && WORKED="${WORKED}1 "

step "2. Finder, set desktop picture"
ERR=$(osascript -e "tell application \"Finder\" to set desktop picture to POSIX file \"$TRY\"" 2>&1)
[ -n "$ERR" ] && say "    said: $ERR"
took && WORKED="${WORKED}2 "

step "3. System Events, then restart WallpaperAgent"
osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$TRY\"" >/dev/null 2>&1
killall WallpaperAgent >/dev/null 2>&1 && say "    WallpaperAgent restarted" || say "    no WallpaperAgent on this system"
took && WORKED="${WORKED}3 "

step "4. the old Dock database"
DB="$HOME/Library/Application Support/Dock/desktoppicture.db"
if [ -f "$DB" ]; then
    sqlite3 "$DB" "update data set value = '$TRY'" >/dev/null 2>&1 && say "    database written"
    killall Dock >/dev/null 2>&1
    took && WORKED="${WORKED}4 "
else
    say "    no such database on this macOS — Sonoma and later removed it"
fi

step "what nimo should use here"
if [ -n "$WORKED" ]; then
    printf '  \033[32mmethods that worked: %s\033[0m\n' "$WORKED"
    case "$WORKED" in
        *0*) say "0 is the good one — no permission, no dialog, works headless" ;;
    esac
else
    printf '  \033[31mnone of them changed the wallpaper\033[0m\n'
    say ""
    case "$ERR" in
        *-1743*|*"Not authorised"*|*"Not authorized"*)
            say "every AppleScript route said -1743, which means this terminal was"
            say "refused Automation permission once and macOS has remembered it."
            say "to be asked again:"
            say ""
            say "    tccutil reset AppleEvents"
            say ""
            say "then run this again and say yes to the box." ;;
        *)
            say "send this whole output, and:" 
            say "    ls -la ~/Library/Application\\ Support/com.apple.wallpaper/Store" ;;
    esac
fi

if [ -n "$BEFORE" ]; then
    printf '\n'
    say "putting yours back …"
    nimo_wall_store_write "$BEFORE" >/dev/null 2>&1
    osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$BEFORE\"" >/dev/null 2>&1
    killall WallpaperAgent >/dev/null 2>&1
    say "now: $(current)"
fi
printf '\n'
