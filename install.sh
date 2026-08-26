#!/usr/bin/env bash
#
# nimo installer — puts `min` on your PATH.
#
#   ./install.sh                 install for the current user
#   ./install.sh --prefix DIR    install the symlink into DIR
#
set -u

REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC="$REPO/min"
PREFIX=""

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) shift; PREFIX="${1:-}" ;;
        --prefix=*) PREFIX="${1#--prefix=}" ;;
        -h|--help)
            echo "usage: ./install.sh [--prefix DIR]"
            exit 0
            ;;
        *) echo "install: unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ ! -f "$SRC" ]; then
    echo "install: cannot find $SRC" >&2
    exit 1
fi

chmod +x "$SRC" 2>/dev/null || true

if [ -z "$PREFIX" ]; then
    if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
        PREFIX="/usr/local/bin"
    elif [ -d /opt/homebrew/bin ] && [ -w /opt/homebrew/bin ]; then
        PREFIX="/opt/homebrew/bin"
    else
        PREFIX="$HOME/.local/bin"
    fi
fi

mkdir -p "$PREFIX" || {
    echo "install: cannot create $PREFIX" >&2
    exit 1
}

TARGET="$PREFIX/min"

if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    echo "install: $TARGET already exists and is not a symlink — leaving it alone" >&2
    exit 1
fi

ln -sf "$SRC" "$TARGET"

# make sure the thing we just installed actually runs
if ! "$TARGET" version >/dev/null 2>&1; then
    echo "install: $TARGET does not run — is the repository complete?" >&2
    exit 1
fi

echo ""
echo "  nimo installed"
echo ""
echo "    $TARGET -> $SRC"
echo ""

case ":${PATH}:" in
    *":$PREFIX:"*)
        echo "  You can now run:  min"
        echo ""
        ;;
    *)
        echo "  $PREFIX is not on your PATH yet. Add it:"
        echo ""
        if [ -n "${ZSH_VERSION:-}" ] || [ "${SHELL##*/}" = "zsh" ]; then
            echo "    echo 'export PATH=\"$PREFIX:\$PATH\"' >> ~/.zshrc"
            echo "    source ~/.zshrc"
        else
            echo "    echo 'export PATH=\"$PREFIX:\$PATH\"' >> ~/.bashrc"
            echo "    source ~/.bashrc"
        fi
        echo ""
        ;;
esac

echo "  Tab completion (optional):"
echo ""
echo "    echo 'source $REPO/completions/min.bash' >> ~/.zshrc"
echo ""
