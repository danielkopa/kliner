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

# Git Bash, MSYS2 and Cygwin are the same shell over a system with no symlinks
# to speak of, and they need a different answer twice below.
WINDOWS=0
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;;
esac

if [ -z "$PREFIX" ]; then
    if [ "$WINDOWS" = "1" ]; then
        # the one directory the bash Git ships puts on PATH for you
        PREFIX="$HOME/bin"
    elif [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
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

NIMO_MARK="# installed by nimo's install.sh"

if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    if ! grep -q "$NIMO_MARK" "$TARGET" 2>/dev/null; then
        echo "install: $TARGET already exists and is not ours — leaving it alone" >&2
        exit 1
    fi
fi

rm -f "$TARGET" 2>/dev/null || true
ln -s "$SRC" "$TARGET" 2>/dev/null || true

# `ln -s` under Git Bash quietly copies the file instead of linking it, unless
# Windows developer mode is on and MSYS is told to use native symlinks. A copy
# of `min` is broken from the moment it lands: `min` finds its own lib/ folder
# beside itself, and beside the copy there is nothing. So the link is checked
# rather than assumed, and where it did not take, a two-line launcher is
# written instead — which works on every system, symlinks or not.
if [ ! -L "$TARGET" ]; then
    rm -f "$TARGET" 2>/dev/null || true
    {
        echo "#!/usr/bin/env bash"
        echo "$NIMO_MARK"
        echo "exec \"$SRC\" \"\$@\""
    } > "$TARGET" || {
        echo "install: cannot write $TARGET" >&2
        exit 1
    }
    chmod +x "$TARGET" 2>/dev/null || true
    HOW="launcher"
else
    HOW="symlink"
fi

# make sure the thing we just installed actually runs
if ! "$TARGET" version >/dev/null 2>&1; then
    echo "install: $TARGET does not run — is the repository complete?" >&2
    exit 1
fi

echo ""
echo "  nimo installed"
echo ""
if [ "$HOW" = "symlink" ]; then
    echo "    $TARGET -> $SRC"
else
    echo "    $TARGET  (a launcher — this system does not do symlinks)"
    echo "    it runs $SRC"
fi
echo ""

# Which file the advice below should name. zsh on a Mac, and the bash Git
# ships everywhere else — telling a Git Bash user to edit ~/.zshrc is advice
# for a shell that is not there.
# The tilde is deliberate: this is a line for the reader to type, not a path
# this script ever opens.
# shellcheck disable=SC2088
if [ "$WINDOWS" = "0" ] && { [ -n "${ZSH_VERSION:-}" ] || [ "${SHELL##*/}" = "zsh" ]; }; then
    RC="~/.zshrc"
else
    RC="~/.bashrc"
fi

case ":${PATH}:" in
    *":$PREFIX:"*)
        echo "  You can now run:  min"
        echo ""
        ;;
    *)
        echo "  $PREFIX is not on your PATH yet. Add it:"
        echo ""
        echo "    echo 'export PATH=\"$PREFIX:\$PATH\"' >> $RC"
        echo "    source $RC"
        echo ""
        ;;
esac

echo "  Tab completion (optional):"
echo ""
echo "    echo 'source $REPO/completions/min.bash' >> $RC"
echo ""
