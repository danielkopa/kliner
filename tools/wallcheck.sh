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

current() {
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
else
    printf '  \033[31mnone of them changed the wallpaper\033[0m\n'
    say ""
    say "if step 1 said nothing at all and still did not take, the setting is"
    say "being written and the screen is not being refreshed — send this output"
    say "and the output of:   ls ~/Library/Application\\ Support/com.apple.wallpaper"
fi

if [ -n "$BEFORE" ]; then
    printf '\n'
    say "putting yours back …"
    osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$BEFORE\"" >/dev/null 2>&1
    killall WallpaperAgent >/dev/null 2>&1
fi
printf '\n'
