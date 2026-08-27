#!/usr/bin/env bash
#
#   bash tools/wallstore.sh
#
# What shape is the wallpaper store on this Mac?
#
# Since Sonoma the wallpaper lives in a plist in your own home folder, which
# is the one way of setting it that needs no permission from anybody. Apple
# changes the shape of that file, so nimo has to be told what it looks like
# rather than guessing — and guessing at the shape of a file it is about to
# write is exactly what nimo should never do.
#
# This prints the structure and nothing else: the keys, and any path that
# looks like a wallpaper. It changes nothing.
set -u

STORE="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"

printf '\n  \033[1mnimo — the shape of the wallpaper store\033[0m\n\n'
printf '  macOS   %s (%s)\n\n' "$(sw_vers -productVersion 2>/dev/null)" "$(uname -m)"

if [ ! -f "$STORE" ]; then
    printf '  no store at %s\n' "$STORE"
    printf '  what is in that folder:\n'
    ls -la "$HOME/Library/Application Support/com.apple.wallpaper" 2>/dev/null | sed 's/^/    /'
    exit 1
fi

printf '  %s\n' "$STORE"
printf '  %s bytes\n\n' "$(wc -c < "$STORE" | tr -d ' ')"

XML=$(plutil -convert xml1 -o - "$STORE" 2>&1) || {
    printf '  plutil could not read it:\n%s\n' "$XML"
    exit 1
}

printf '  \033[1mevery key in it, and how often\033[0m\n\n'
printf '%s\n' "$XML" \
    | sed -n 's/.*<key>\([^<]*\)<\/key>.*/\1/p' \
    | sort | uniq -c | sort -rn | sed 's/^/    /'

printf '\n  \033[1manything that looks like a file\033[0m\n\n'
FOUND=$(printf '%s\n' "$XML" | grep -n 'file:///\|\.heic\|\.jpg\|\.png\|\.HEIC' | head -20)
if [ -n "$FOUND" ]; then
    printf '%s\n' "$FOUND" | sed 's/^/    /'
else
    printf '    none — the path is not stored as text in this file\n'
fi

printf '\n  \033[1mthe first 60 lines, so the nesting is visible\033[0m\n\n'
printf '%s\n' "$XML" | head -60 | cut -c1-100 | sed 's/^/    /'

printf '\n  \033[1mis there a data blob holding it\033[0m\n\n'
BLOBS=$(printf '%s\n' "$XML" | grep -c '<data>' || true)
printf '    %s <data> blocks\n' "${BLOBS:-0}"
if [ "${BLOBS:-0}" != "0" ]; then
    printf '    the largest, decoded, first 200 bytes:\n'
    printf '%s\n' "$XML" \
        | awk '/<data>/{f=1;b="";next} /<\/data>/{f=0; if (length(b)>length(m)) m=b; next} f{gsub(/[ \t]/,"",$0); b=b $0} END{print m}' \
        | base64 -d 2>/dev/null | head -c 200 | strings | sed 's/^/      /'
fi
printf '\n'
