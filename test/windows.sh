#!/usr/bin/env bash
#
#   nimo's Windows suite.
#
#       bash test/windows.sh
#
#   Under Git Bash, MSYS2 or Cygwin, $HOME is already C:/Users/<name>, so the
#   rule that keeps nimo inside your home folder holds there with nothing
#   widened for the occasion. What does change is where things live: the
#   Desktop is usually in OneDrive, the caches are under AppData, and the
#   Recycle Bin is not a folder anyone should be deleting out of.
#
#   This runs the real code against a faked Windows, on any machine.
#
set -u

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
MIN="$ROOT/min"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    G=$'\033[32m'; R=$'\033[31m'; D=$'\033[2m'; B=$'\033[1m'; Z=$'\033[0m'
else
    G=""; R=""; D=""; B=""; Z=""
fi

PASS=0
FAIL=0
FAILED=""
QUIET=0
case "${1:-}" in
    -q|--quiet) QUIET=1 ;;
esac

check() {
    if eval "$2" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        [ "$QUIET" = "1" ] || printf '  %s✓%s %s\n' "$G" "$Z" "$1"
    else
        FAIL=$((FAIL + 1))
        FAILED="$FAILED
    $1"
        printf '  %s✗%s %s\n' "$R" "$Z" "$1"
    fi
}

BOX=$(mktemp -d "${TMPDIR:-/tmp}/nimo-windows.XXXXXX") || exit 1
trap 'rm -rf "$BOX"' EXIT INT TERM

FAKE="$BOX/fakebin"
mkdir -p "$FAKE"
cat > "$FAKE/uname" <<'SHIM'
#!/bin/sh
case "${1:-}" in
    -s) echo "MINGW64_NT-10.0-22631" ;;
    -m) echo x86_64 ;;
    -r) echo "3.4.10" ;;
    *)  echo "MINGW64_NT-10.0-22631" ;;
esac
SHIM
chmod +x "$FAKE"/*

win() { PATH="$FAKE:$PATH" HOME="$BOX" bash "$MIN" "$@" </dev/null; }

# a profile that looks like a signed-in Windows: the Desktop has moved into
# OneDrive and left an empty one behind, which is exactly the trap
mkdir -p "$BOX/Desktop" \
         "$BOX/OneDrive/Desktop" \
         "$BOX/Downloads" \
         "$BOX/Documents" \
         "$BOX/AppData/Local/Temp" \
         "$BOX/AppData/Roaming/npm-cache/_cacache" \
         "$BOX/AppData/Local/pip/Cache"

touch "$BOX/OneDrive/Desktop/report.pdf" \
      "$BOX/OneDrive/Desktop/photo.png" \
      "$BOX/OneDrive/Desktop/Screenshot 2026-08-01 120000.png"
touch "$BOX/Downloads/setup.exe" "$BOX/Downloads/notes.txt"
dd if=/dev/zero of="$BOX/AppData/Local/Temp/blob" bs=1024 count=5120 2>/dev/null
dd if=/dev/zero of="$BOX/AppData/Roaming/npm-cache/_cacache/pkg" bs=1024 count=2048 2>/dev/null

printf '\n  %snimo windows suite%s\n' "$B" "$Z"
printf '  %sreal nimo code, fake Git Bash underneath · %s%s\n\n' "$D" "$BOX" "$Z"

# ---- does it know where it is? -------------------------------------------

check "nimo knows this is windows"        "[ \"\$(PATH=\"$FAKE:\$PATH\" bash -c '. $ROOT/lib/core.sh; nimo_platform')\" = windows ]"
check "and does not think it is a mac"    "! win doctor -q --no-color | grep -q macOS"
check "doctor still reports the disk"     "win doctor -q --no-color | grep -q Disk"

# ---- the desktop that moved into OneDrive --------------------------------

check "it finds the desktop in OneDrive"  "win desktop --dry-run -q --no-color | grep -q 'Screenshots'"
check "and counts what is really there"   "win desktop --dry-run -q --no-color | grep -q '3 items'"
check "the empty one is not the answer"   "[ \"\$(PATH=\"$FAKE:\$PATH\" HOME=\"$BOX\" bash -c '. $ROOT/lib/core.sh; nimo_desktop_dir')\" = \"$BOX/OneDrive/Desktop\" ]"

win desktop -y -q --no-color >/dev/null 2>&1
check "sorting puts them in OneDrive too" "[ -f '$BOX/OneDrive/Desktop/Tidy/Documents/report.pdf' ]"
check "and the screenshot with them"      "[ -f '$BOX/OneDrive/Desktop/Tidy/Screenshots/Screenshot 2026-08-01 120000.png' ]"
win desktop --undo -q --no-color >/dev/null 2>&1
check "undo puts them back where taken"   "[ -f '$BOX/OneDrive/Desktop/report.pdf' ]"

win downloads -y -q --no-color >/dev/null 2>&1
check "downloads sorts too"               "[ -f '$BOX/Downloads/Tidy/Documents/notes.txt' ]"
win downloads --undo -q --no-color >/dev/null 2>&1

# ---- windows junk, not mac junk ------------------------------------------

check "it looks under AppData"            "win preview -q --no-color | grep -q 'Temp files'"
check "it finds the npm cache there"      "win preview -q --no-color | grep -q 'npm / yarn cache'"
check "it adds them up"                   "win preview -q --no-color | grep -q '7.0 MB'"
check "it does not look for ~/Library"    "! win preview -q --no-color | grep -q 'Xcode'"

# ---- what windows simply does not have -----------------------------------

check "the dock is not a windows thing"   "win dock -q --no-color | grep -q 'macOS'"
check "nor is the wallpaper command"      "win wallpaper -q --no-color | grep -q 'macOS'"
check "nor are the macOS preferences"     "win setup -y -q --no-color | grep -q 'macOS'"
check "nor is hiding the desktop icons"   "win zen -q --no-color | grep -q 'macOS'"
check "nor the appearance switch"         "win dark -q --no-color | grep -q 'macOS'"
check "nor the unused-apps list"          "win apps -q --no-color | grep -q 'macOS'"

check "the recycle bin is left to windows" "win empty -q --no-color | grep -q 'Recycle Bin'"
check "and it says how to empty it"       "win empty -q --no-color | grep -q 'Clear-RecycleBin'"
check "it does not delete anything there" "win empty -y -q --no-color >/dev/null 2>&1; [ -d '$BOX/OneDrive/Desktop' ]"

# ---- the menu only offers what windows can do ----------------------------
#
# It used to be a fixed list of seven. Windows was offered a Dock it does not
# have and a Recycle Bin nimo is not allowed to empty, and picking either got
# you an apology instead of a clean desktop.

wmenu() { printf '\n' | PATH="$FAKE:$PATH" HOME="$BOX" bash "$MIN" clear --no-color 2>&1; }

check "the menu lists what it offers"     "wmenu | grep -q '^ *1  '"
check "no dock on windows"                "! wmenu | grep -q 'Dock'"
check "no trash to empty either"          "! wmenu | grep -q 'Trash'"
check "the disk is still on offer"        "wmenu | grep -q 'Disk'"
check "and the numbers match the rows"    "[ \"\$(wmenu | sed -n 's/.*Which one? 1-\\([0-9]*\\).*/\\1/p')\" = \"\$(wmenu | grep -c '^ *[0-9]  ')\" ]"

# the menu counted ~/Desktop while `min screenshots` read OneDrive's, so a
# signed-in Windows was always told it had none
check "the menu counts OneDrive's shots"  "wmenu | grep -q '1 loose'"
check "and the command agrees with it"    "win screenshots --dry-run -q --no-color | grep -q '1 file'"

# ---- windows, spelled the way people say it ------------------------------

check "doctor says Windows, not MINGW"    "win doctor -q --no-color | grep -q 'Windows 11'"
check "and which bash it is running in"   "win doctor -q --no-color | grep -q 'Git Bash'"
check "no MINGW64_NT anywhere in it"      "! win doctor -q --no-color | grep -q 'MINGW64_NT'"
check "the bin is named, not counted"     "win doctor -q --no-color | grep -q 'Recycle Bin'"

# ---- the parts that work everywhere --------------------------------------

check "top works"                         "win top -q --no-color | grep -q '█'"
check "duplicates works"                  "win duplicates -q --no-color | grep -q 'copies\\|more than once'"
check "the prompt works"                  "printf '/quit\\n' | NIMO_REPL_FORCE=1 PATH=\"$FAKE:\$PATH\" HOME=\"$BOX\" bash \"$MIN\" -q --no-color 2>&1 | grep -q 'nimo ›'"
check "the guard still refuses outside"   "PATH=\"$FAKE:\$PATH\" HOME=\"$BOX\" bash -c '. $ROOT/lib/ui.sh; . $ROOT/lib/core.sh; nimo_is_protected /c/Windows'"

printf '\n'
if [ "$FAIL" -eq 0 ]; then
    printf '  %s✓ %d passed%s\n\n' "$G" "$PASS" "$Z"
    exit 0
else
    printf '  %s%d passed, %d failed%s%s\n\n' "$R" "$PASS" "$FAIL" "$FAILED" "$Z"
    exit 1
fi
