#!/usr/bin/env bash
#
#   app/install-app.sh — build Nimo.app on this Mac and put it in place.
#
#   One command, from anywhere:
#
#       bash ~/nimo/app/install-app.sh
#
#   It builds the app from this repository, moves it into Applications, and
#   opens it. Because it was built here rather than downloaded, macOS has
#   nothing to warn you about — no right-click, no dialog. It just runs.
#
set -eu

root=$(cd -P "$(dirname "$0")/.." && pwd)
cd "$root"

cyan=""; dim=""; red=""; off=""
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    cyan=$'\033[38;5;80m'; dim=$'\033[2m'; red=$'\033[31m'; off=$'\033[0m'
fi

say()  { printf '  %s\n' "$1"; }
good() { printf '  %s✓%s %s\n' "$cyan" "$off" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$red" "$off" "$1" >&2; }

printf '\n  %s◍ nimo%s  %sbuilding the app%s\n\n' "$cyan" "$off" "$dim" "$off"

if [ "$(uname -s)" != "Darwin" ]; then
    bad "This builds a Mac app, and this is not a Mac."
    exit 1
fi

# --- the compiler -------------------------------------------------------
# swiftc comes with Apple's command line tools. If git works on this Mac
# they are almost certainly here already.
if ! command -v swiftc >/dev/null 2>&1; then
    bad "Apple's command line tools are not installed."
    printf '\n'
    say "Run this, click Install, wait for it to finish, then run me again:"
    printf '\n      %sxcode-select --install%s\n\n' "$cyan" "$off"
    exit 1
fi

# --- build it -----------------------------------------------------------
if ! bash "$root/app/build.sh"; then
    bad "The build failed. The output above says why —"
    say "send it to me and I will fix it."
    exit 1
fi

app="$root/app/build/Nimo.app"
[ -d "$app" ] || { bad "The build said it worked, but there is no app."; exit 1; }

# --- where it goes ------------------------------------------------------
# /Applications if this account may write there, your own Applications
# folder if not. Never sudo — nimo does not ask for an administrator, and
# an installer that does is a different kind of program.
dest="/Applications"
if [ ! -w "$dest" ]; then
    dest="$HOME/Applications"
    mkdir -p "$dest"
fi

# A running copy holds its own bundle open, so it goes first.
if pgrep -x Nimo >/dev/null 2>&1; then
    osascript -e 'tell application "Nimo" to quit' >/dev/null 2>&1 || killall Nimo 2>/dev/null || true
    sleep 1
fi

if [ -d "$dest/Nimo.app" ]; then
    rm -rf "$dest/Nimo.app.old"
    mv "$dest/Nimo.app" "$dest/Nimo.app.old"
fi

ditto "$app" "$dest/Nimo.app"
rm -rf "$dest/Nimo.app.old"

# Built here, not downloaded — but a stray quarantine flag from anywhere in
# the tree would still make macOS ask. Take it off and there is nothing to ask.
xattr -dr com.apple.quarantine "$dest/Nimo.app" 2>/dev/null || true

open "$dest/Nimo.app"

printf '\n'
good "Nimo is in $(printf '%s' "$dest" | sed "s|$HOME|~|")"
good "It is running — look at the top right of your screen, beside the clock."
printf '\n'
say "${dim}Click the face. Everything asks before it changes anything,${off}"
say "${dim}and \"Put it all back\" reverses the lot.${off}"
printf '\n'
say "${dim}To have it there every morning: the menu has \"Open nimo at login\".${off}"
say "${dim}To remove it: drag Nimo out of Applications. That is all it is.${off}"
printf '\n'
