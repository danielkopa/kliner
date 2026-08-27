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

# A `reg` that is real enough for nimo, and only for nimo. One line per value:
#   key<TAB>name<TAB>type<TAB>data
REG="$BOX/registry"
: > "$REG"

cat > "$FAKE/reg" <<SHIM
#!/bin/sh
REG="$REG"
SHIM
cat >> "$FAKE/reg" <<'SHIM'
verb="${1:-}"; shift 2>/dev/null || true
key="${1:-}"; shift 2>/dev/null || true
name=""; type="REG_SZ"; data=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        /v) name="$2"; shift 2 ;;
        /t) type="$2"; shift 2 ;;
        /d) data="$2"; shift 2 ;;
        /f) shift ;;
        *)  shift ;;
    esac
done

case "$verb" in
    query)
        # awk on exact fields, not grep: a registry key is full of backslashes,
        # and grep reads \S and \W as patterns of its own. Through ENVIRON,
        # not -v, because an awk assignment expands escapes too — -v k="HKCU\S…"
        # arrives as HKCUS… and matches nothing.
        line=$(k="$key" n="$name" awk -F'	' '$1 == ENVIRON["k"] && $2 == ENVIRON["n"]' "$REG" | tail -1)
        [ -n "$line" ] || { echo "ERROR: The system was unable to find the specified registry key or value." >&2; exit 1; }
        echo
        echo "$key"
        printf '    %s    %s    %s
' "$(printf '%s' "$line" | cut -f2)"                                       "$(printf '%s' "$line" | cut -f3)"                                       "$(printf '%s' "$line" | cut -f4-)"
        echo
        exit 0 ;;
    add)
        k="$key" n="$name" awk -F'	' '!($1 == ENVIRON["k"] && $2 == ENVIRON["n"])' "$REG" > "$REG.new"
        mv "$REG.new" "$REG"
        printf '%s	%s	%s	%s
' "$key" "$name" "$type" "$data" >> "$REG"
        exit 0 ;;
    delete)
        k="$key" n="$name" awk -F'	' '!($1 == ENVIRON["k"] && $2 == ENVIRON["n"])' "$REG" > "$REG.new"
        mv "$REG.new" "$REG"
        exit 0 ;;
esac
exit 1
SHIM

# the poke Windows wants after a wallpaper or a theme changes
cat > "$FAKE/RUNDLL32.EXE" <<SHIM
#!/bin/sh
echo "\$*" >> "$BOX/rundll"
exit 0
SHIM
cp "$FAKE/RUNDLL32.EXE" "$FAKE/rundll32.exe"

chmod +x "$FAKE"/*

# Windows itself, and the wallpapers it ships with
mkdir -p "$BOX/Windows/Web/Wallpaper/Windows" \
         "$BOX/Windows/Web/Wallpaper/Theme1" \
         "$BOX/Windows/Web/4K/Wallpaper/Windows"
: > "$BOX/Windows/Web/Wallpaper/Windows/img0.jpg"
: > "$BOX/Windows/Web/Wallpaper/Theme1/img1.jpg"
: > "$BOX/Windows/Web/Wallpaper/Theme1/img2.jpg"
: > "$BOX/Windows/Web/4K/Wallpaper/Windows/img0_1920x1200.jpg"

win() { PATH="$FAKE:$PATH" HOME="$BOX" SYSTEMROOT="$BOX/Windows" bash "$MIN" "$@" </dev/null; }
reg_has() { grep -q "$1" "$REG"; }
regval() { n="$1" v="$2" awk -F'\t' '$2 == ENVIRON["n"] && $4 == ENVIRON["v"] { found = 1 } END { exit !found }' "$REG"; }

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
check "nor the unused-apps list"          "win apps -q --no-color | grep -q 'macOS'"

# ---- what windows does have --------------------------------------------
#
# These three used to print "that is a macOS thing" and stop. Everything they
# touch here is HKCU — the signed-in user's own settings, the counterpart of
# `defaults` on a Mac. Nothing under HKLM, nothing needing an administrator,
# and every value written down first so min undo can put it back.

check "wallpaper finds what windows ships" "win wallpaper --list -q --no-color | grep -q 'img0'"
check "and calls it a pc, not a mac"      "win wallpaper --list -q --no-color | grep -q 'this pc'"
check "it does not offer macOS folders"   "! win wallpaper --list -q --no-color | grep -qi 'solid colors'"

win wallpaper -y -q --no-color >/dev/null 2>&1
check "setting one writes the registry"   "awk -F'\t' '\$2 == \"WallPaper\"' '$REG' | grep -q 'REG_SZ'"
check "as a path windows can read"        "awk -F'\t' '\$2 == \"WallPaper\"' '$REG' | grep -q 'Web'"
check "backslashed, not slashed"          "awk -F'\t' '\$2 == \"WallPaper\"' '$REG' | grep -q '\\\\'"
check "and pokes windows to redraw"       "grep -q 'UpdatePerUserSystemParameters' '$BOX/rundll'"

check "dark mode is a registry value"     "win dark -y -q --no-color >/dev/null 2>&1; reg_has 'AppsUseLightTheme'"
check "0 means dark, backwards on purpose" "regval AppsUseLightTheme 0"
check "the shell chrome follows the apps" "reg_has 'SystemUsesLightTheme'"
check "and nimo reads its own change back" "win dark -q --no-color | grep -q 'already dark'"
check "light switches it back"            "win light -y -q --no-color >/dev/null 2>&1; regval AppsUseLightTheme 1"

check "zen promises to delete nothing"    "win zen --dry-run -q --no-color | grep -q 'stay exactly where they are'"
check "and a dry run writes nothing"      "! reg_has 'HideIcons'"
check "zen hides the desktop icons"       "win zen -y -q --no-color >/dev/null 2>&1; regval HideIcons 1"
check "--restore brings them back"        "win zen --restore -y -q --no-color >/dev/null 2>&1; regval HideIcons 0"
check "zen deletes nothing on the desktop" "[ -f '$BOX/OneDrive/Desktop/report.pdf' ]"

# ---- a setup that fits the machine it is on ------------------------------

check "setup offers windows groups"       "win setup --list -q --no-color | grep -q explorer"
check "and not the macOS ones"            "! win setup --list -q --no-color | grep -q 'Finder\|screenshots'"
check "the example names groups it has"   "! win setup --list -q --no-color | grep -q 'only dock,finder'"
check "a dry run shows the reg commands"  "win setup --dry-run -q --no-color | grep -q 'reg add'"
check "and writes nothing"                "! reg_has 'HideFileExt'"

win setup -y -q --no-color >/dev/null 2>&1
check "extensions get shown"              "regval HideFileExt 0"
check "explorer opens to This PC"         "regval LaunchTo 1"
check "the sidebar ads go"                "regval ShowSyncProviderNotifications 0"
check "so does the task view button"      "regval ShowTaskViewButton 0"
check "search becomes an icon"            "regval SearchboxTaskbarMode 1"
check "--only takes one group"            "win setup --only explorer --dry-run -q --no-color | grep -q HideFileExt"
check "and leaves the other alone"        "! win setup --only explorer --dry-run -q --no-color | grep -q TaskbarDa"

# ---- and all of it comes back -------------------------------------------
#
# A value that was never set has to be unset again, not left behind. That
# needs the registry, not `defaults`, which is not on this machine at all —
# so the log says REG_NONE rather than leaving the type blank.

check "every change was written down"     "ls '$BOX/.nimo/backups'/setup-*.tsv >/dev/null 2>&1"
check "an unset value is logged as such"  "grep -q REG_NONE '$BOX/.nimo/backups'/setup-*.tsv"

win zen -y -q --no-color >/dev/null 2>&1
win setup --restore -y -q --no-color >/dev/null 2>&1
check "restore reaches the registry"      "regval HideIcons 0"

# The line that was wrong: an absent value was logged with no type at all, so
# the restore handed it to `defaults`, which is not on this machine, and the
# value nimo had invented stayed behind for good. Replayed straight, so the
# branch is tested and not merely present.
FIRST=$(grep -l AppsUseLightTheme "$BOX/.nimo/backups"/setup-*.tsv | head -1)
replay() {
    PATH="$FAKE:$PATH" HOME="$BOX" bash -c '
        . '"$ROOT"'/lib/ui.sh; . '"$ROOT"'/lib/core.sh; . '"$ROOT"'/lib/win.sh
        . '"$ROOT"'/lib/wall.sh; . '"$ROOT"'/lib/setup.sh
        nimo_init_colors; NIMO_UNDO_QUIET=1
        nimo_setup_restore "$1"' _ "$1" >/dev/null 2>&1
}
check "a value nimo invented is unset"    "replay \"\$FIRST\"; ! reg_has 'AppsUseLightTheme'"

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

# ---- and it will not delete your pc either -------------------------------
#
# The same spellings the Linux suite tries, on a profile that looks like
# Windows: C:/Users/<name>, with the desktop off in OneDrive. A guard that
# only holds on the platform it was written on is not a guard.

wguard() { PATH="$FAKE:$PATH" HOME="$1" bash -c '. '"$ROOT"'/lib/ui.sh; . '"$ROOT"'/lib/core.sh; nimo_is_protected "$1"' _ "$2"; }

check "windows itself is off limits"      "wguard '$BOX' /c/Windows/System32"
check "so are the program files"          "wguard '$BOX' '/c/Program Files'"
check "and another account's profile"     "wguard '$BOX' /c/Users/someone-else"
check "your profile itself is too"        "wguard '$BOX' '$BOX'"
check "a dot does not open it"            "wguard '$BOX' '$BOX/.'"
check "nor two slashes"                   "wguard '$BOX' '$BOX//'"
check "nor a walk back out of it"         "wguard '$BOX' '$BOX/AppData/../..'"
check "AppData under it is still fine"    "! wguard '$BOX' '$BOX/AppData/Local/Temp'"
check "and OneDrive's desktop with it"    "! wguard '$BOX' '$BOX/OneDrive/Desktop'"

# A HOME that Windows handed over with backslashes is not a path this shell
# can compare against anything. nimo refuses rather than guesses.
check "a backslashed HOME deletes nothing" "wguard 'C:\\Users\\daniel' 'C:\\Users\\daniel\\Downloads'"
check "an empty one deletes nothing"      "wguard '' /c/Users/daniel/Downloads"

check "cleaning refuses the profile root" "PATH=\"$FAKE:\$PATH\" HOME=\"$BOX\" bash -c '. $ROOT/lib/ui.sh; . $ROOT/lib/core.sh; nimo_init_colors; nimo_purge_children \"\$HOME/.\"' 2>&1 | grep -q 'refusing'"
check "and the desktop is still there"    "[ -f '$BOX/OneDrive/Desktop/report.pdf' ]"

printf '\n'
if [ "$FAIL" -eq 0 ]; then
    printf '  %s✓ %d passed%s\n\n' "$G" "$PASS" "$Z"
    exit 0
else
    printf '  %s%d passed, %d failed%s%s\n\n' "$R" "$PASS" "$FAIL" "$FAILED" "$Z"
    exit 1
fi
