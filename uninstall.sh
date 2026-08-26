#!/usr/bin/env bash
#
# Removes the `min` symlink. Your repository stays where it is.
#
set -u

removed=0
for dir in /usr/local/bin /opt/homebrew/bin "$HOME/.local/bin" "$HOME/bin"; do
    link="$dir/min"
    if [ -L "$link" ]; then
        rm -f "$link" && {
            echo "  removed $link"
            removed=1
        }
    fi
done

if [ "$removed" = "0" ]; then
    echo "  nothing to remove — no min symlink found"
else
    echo ""
    echo "  nimo uninstalled. The repository itself was not touched."
fi
