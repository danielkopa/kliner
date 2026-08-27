#!/usr/bin/env bash
#
# Removes the `min` symlink, or the launcher written in its place on a system
# without symlinks. Your repository stays where it is.
#
set -u

removed=0
NIMO_MARK="# installed by nimo's install.sh"

# Two shapes to look for: the symlink, and the two-line launcher install.sh
# writes where symlinks do not work — Git Bash, MSYS2, Cygwin. The launcher is
# a plain file, so it is only removed when it says it is ours; a `min` that
# somebody else put there is left exactly where it is.
for dir in /usr/local/bin /opt/homebrew/bin "$HOME/.local/bin" "$HOME/bin"; do
    link="$dir/min"
    if [ -L "$link" ]; then
        rm -f "$link" && {
            echo "  removed $link"
            removed=1
        }
    elif [ -f "$link" ] && grep -q "$NIMO_MARK" "$link" 2>/dev/null; then
        rm -f "$link" && {
            echo "  removed $link"
            removed=1
        }
    fi
done

for dir in /usr/local/share/man/man1 /opt/homebrew/share/man/man1 "$HOME/.local/share/man/man1"; do
    page="$dir/min.1"
    if [ -L "$page" ]; then
        rm -f "$page" && {
            echo "  removed $page"
            removed=1
        }
    fi
done

if [ "$removed" = "0" ]; then
    echo "  nothing to remove — no min symlink found"
else
    echo ""
    echo "  nimo uninstalled. The repository itself was not touched."
    echo ""
    echo "  Your settings and undo history are still in ~/.nimo"
    echo "  Remove them too with:  rm -rf ~/.nimo"
fi
