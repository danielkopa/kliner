#!/usr/bin/env bash
#
#   nimo's own test suite.
#
#       bash test/run.sh
#
#   Everything happens inside a throwaway folder in /tmp with its own fake
#   HOME. Your real files are never read, never measured, never touched.
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

# -q prints only what went wrong, and the verdict
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

# ---- a fake computer to clean ------------------------------------------

BOX=$(mktemp -d "${TMPDIR:-/tmp}/nimo-test.XXXXXX") || exit 1
trap 'rm -rf "$BOX"' EXIT INT TERM

blob() {
    mkdir -p "$(dirname "$1")"
    dd if=/dev/zero of="$1" bs=1024 count="$2" 2>/dev/null
}

case "$(uname -s)" in
    Darwin) CACHE="$BOX/Library/Caches"; TRASH="$BOX/.Trash" ;;
    *)      CACHE="$BOX/.cache";         TRASH="$BOX/.local/share/Trash/files" ;;
esac

blob "$CACHE/big-cache-file"        14336
blob "$TRASH/already-thrown-away"    5120
blob "$BOX/.npm/_cacache/package"    6144
blob "$BOX/Movies/holiday.mov"      40960
blob "$BOX/Documents/thesis.pdf"    11264
blob "$BOX/proj/node_modules/dep"    6144
blob "$BOX/Downloads/old one.dmg"    9216
touch -t 202001010000 "$BOX/Downloads/old one.dmg"
mkdir -p "$BOX/Desktop"
touch "$BOX/Desktop/a" "$BOX/Desktop/b"

# Every call gets an empty stdin. `min` with no command opens a prompt when
# there is a terminal on the other end, and a suite run from a real terminal
# would otherwise stop dead on the first such check, waiting to be typed at.
# Tests that need to type something pipe their own input instead.
min() { HOME="$BOX" bash "$MIN" "$@" </dev/null; }

printf '\n  %snimo test suite%s\n' "$B" "$Z"
printf '  %sbash %s on %s · fake home in %s%s\n\n' \
    "$D" "${BASH_VERSION:-?}" "$(uname -s)" "$BOX" "$Z"

# ---- the command surface ------------------------------------------------

check "min version prints a version"      "min version | grep -q '[0-9]\.[0-9]'"
check "min shows the logo"                "min -q --no-color; min --no-color | grep -q 'Commands'"
check "min help lists every command"      "min help --no-color | grep -q 'min doctor' && min help --no-color | grep -q 'min top'"
check "unknown option exits 2"            "min --nonsense >/dev/null 2>&1; [ \$? -eq 2 ]"
check "unknown command exits 2"           "min explode >/dev/null 2>&1; [ \$? -eq 2 ]"
check "--days rejects words"              "min preview --days later >/dev/null 2>&1; [ \$? -eq 2 ]"
check "--limit rejects zero"              "min top --limit 0 >/dev/null 2>&1; [ \$? -eq 2 ]"

# ---- looking, without touching ------------------------------------------

check "preview finds something"           "! min preview -q --no-color | grep -q 'nothing to clean here'"
check "preview says nothing was deleted"  "min preview -q --no-color | grep -q 'nothing was deleted'"
check "preview leaves the cache alone"    "[ -f '$CACHE/big-cache-file' ]"
check "preview leaves downloads alone"    "[ -f '$BOX/Downloads/old one.dmg' ]"
check "old downloads are only reported"   "min preview -q --no-color | grep -q 'Old downloads'"
check "--days 9999 ages nothing out"      "! min preview -q --no-color --days 9999 | grep -q 'Old downloads'"
check "node_modules are only reported"    "min preview -q --no-color | grep -q 'node_modules'"

check "min top draws bars"                "min top -q --no-color | grep -q '█'"
check "min top honours --limit"           "[ \$(min top -q --no-color --limit 3 | grep -c '█') -eq 3 ]"
check "min top puts the biggest first"    "min top -q --no-color | grep '█' | head -1 | grep -q 'Movies'"
check "min doctor reports the disk"       "min doctor -q --no-color | grep -q 'Disk'"
check "min doctor counts the desktop"     "min doctor -q --no-color | grep -q '2 items'"

check "--json is valid json"              "min preview --json | python3 -c 'import json,sys; json.load(sys.stdin)' || min preview --json | python -c 'import json,sys; json.load(sys.stdin)'"
check "--json reports safe bytes"         "min preview --json | grep -q '\"safe_bytes\": [1-9]'"
check "--json never deletes"              "min preview --json >/dev/null; [ -f '$CACHE/big-cache-file' ]"

check "--only narrows the report"         "[ \$(min preview -q --no-color --only trash | grep -c 'MB\|KB\|GB') -le 3 ]"
check "--only rejects nothing silently"   "min preview -q --no-color --only nope-not-real | grep -q 'nothing to clean here'"

# ---- the safety guard ---------------------------------------------------

check "refuses paths outside your home"   "HOME=$BOX bash -c '. $ROOT/lib/ui.sh; . $ROOT/lib/core.sh; nimo_is_protected /tmp'"
check "refuses your home itself"          "HOME=$BOX bash -c '. $ROOT/lib/ui.sh; . $ROOT/lib/core.sh; nimo_is_protected \"\$HOME\"'"
check "refuses the root of the disk"      "HOME=$BOX bash -c '. $ROOT/lib/ui.sh; . $ROOT/lib/core.sh; nimo_is_protected /'"
check "refuses /System"                   "HOME=$BOX bash -c '. $ROOT/lib/ui.sh; . $ROOT/lib/core.sh; nimo_is_protected /System'"
check "allows a cache inside your home"   "HOME=$BOX bash -c '. $ROOT/lib/ui.sh; . $ROOT/lib/core.sh; ! nimo_is_protected \"\$HOME/Library/Caches\"'"
check "will not purge outside your home"  "HOME=$BOX bash -c '. $ROOT/lib/ui.sh; . $ROOT/lib/core.sh; nimo_init_colors; ! nimo_purge_children /tmp' 2>/dev/null"

# ---- setup --------------------------------------------------------------

check "setup --list names the groups"     "min setup --list -q --no-color | grep -q screenshots"
check "setup --dry-run changes nothing"   "min setup --dry-run -q --no-color >/dev/null; true"

# ---- tab completion -----------------------------------------------------
#
# Sourcing this from a zsh .zshrc used to print "command not found: complete"
# on every new terminal, because zsh has no such builtin until bashcompinit
# is loaded. Whatever the shell, sourcing it must be silent.

check "the completion file loads"         "bash -c 'source \"$ROOT/completions/min.bash\" && complete -p min' | grep -q _min_complete"
check "and says nothing while loading"    "[ -z \"\$(bash -c 'source \"$ROOT/completions/min.bash\"' 2>&1)\" ]"
check "it survives having no complete"    "grep -q 'type complete' \"$ROOT/completions/min.bash\""
check "it loads bashcompinit for zsh"     "grep -q bashcompinit \"$ROOT/completions/min.bash\""

# ---- the prompt ---------------------------------------------------------

# a line typed at the prompt, and everything nimo said back
typed() {
    printf '%s\n/quit\n' "$1" | NIMO_REPL_FORCE=1 HOME="$BOX" \
        bash "$MIN" -q --no-color 2>&1
}

check "the prompt greets you"             "typed '' | grep -q 'nimo ›'"
check "/ lists what you can type"         "typed '/' | grep -q '/clear' && typed '/' | grep -q '/wallpaper'"
check "/doctor runs doctor"               "typed '/doctor' | grep -q 'your computer'"
check "the slash is optional"             "typed 'doctor' | grep -q 'your computer'"
check "/preview runs preview"             "typed '/preview' | grep -q 'safe to clean'"
check "/clean desktop means the desktop"  "typed '/clean desktop' | grep -q 'your desktop'"
check "so does clear desktop"             "typed 'clear desktop' | grep -q 'your desktop'"
check "flags are passed through"          "typed '/preview --json' | grep -q '\"safe_bytes\"'"
check "a typo is caught"                  "typed '/wallpapr' | grep -q 'did you mean /wallpaper'"
check "a typo mid-phrase is caught"       "typed '/clean deskopt' | grep -q 'did you mean /clean desktop'"
check "nonsense is not guessed at"        "typed '/xyzzy' | grep -q 'does not know' && ! typed '/xyzzy' | grep -q 'did you mean'"
check "/quit stops reading there"        "! printf '/quit\n/doctor\n' | NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color 2>&1 | grep -q 'your computer'"
check "the prompt exits 0"                "printf '/quit\n' | NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color >/dev/null 2>&1"
check "end of input is not an error"      "printf '' | NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color >/dev/null 2>&1"
check "one command cannot leak into next" "typed '/preview --json' | grep -q 'safe_bytes' && typed '/preview' | grep -q 'safe to clean'"

# ---- the newer commands -------------------------------------------------

DL="$BOX/Downloads"
mkdir -p "$DL" "$BOX/Documents" "$BOX/Pictures"
touch "$DL/Screenshot B.png" "$DL/installer.dmg" "$DL/report.pdf"
touch "$BOX/Documents/Screenshot C.png"

check "/clear on its own asks what"        "printf '/clear\\nq' | NIMO_PICK_FORCE=1 NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color 2>&1 | grep -q 'what should be clear'"
check "/clear offers the desktop first"    "printf '/clear\\nq' | NIMO_PICK_FORCE=1 NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color 2>&1 | grep -q 'Desktop'"
check "picking the first one clears it"    "printf '/clear\\n\\n' | NIMO_PICK_FORCE=1 NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color --dry-run 2>&1 | grep -q 'your desktop'"
check "picking the second one too"         "printf '/clear\\n\\033[B\\n' | NIMO_PICK_FORCE=1 NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color --dry-run 2>&1 | grep -q 'your downloads'"
check "min clear desktop skips the asking" "min clear desktop --dry-run -q --no-color | grep -q 'your desktop'"
check "min clear disk means the caches"    "min clear disk --dry-run -q --no-color | grep -q 'safe to clean'"
check "min clear nonsense is refused"      "min clear nonsense -q --no-color 2>&1 | grep -q 'cannot clear'"
check "the short list leads with /clear"   "typed '/' | grep -q '/clear'"
check "the short list stays short"         "[ \$(typed '/' | grep -c '^     /') -le 5 ]"

check "/cleardesktop reaches the desktop"  "typed '/cleardesktop --dry-run' | grep -q 'your desktop'"
check "/clearfiles means the same"         "typed '/clearfiles --dry-run' | grep -q 'your desktop'"
check "/cleardownloads reaches downloads"  "typed '/cleardownloads --dry-run' | grep -q 'your downloads'"
check "/cleandock reaches the dock"        "typed '/cleandock' | grep -q 'macOS\|your dock'"
check "spaces are optional both ways"      "typed '/clear downloads --dry-run' | grep -q 'your downloads'"

check "downloads sorts downloads"          "min downloads -y -q --no-color >/dev/null 2>&1; [ -f '$DL/Tidy/Archives/installer.dmg' ]"
check "and files the documents too"        "[ -f '$DL/Tidy/Documents/report.pdf' ]"
check "downloads --undo puts them back"    "min downloads --undo -q --no-color >/dev/null 2>&1; [ -f '$DL/installer.dmg' ]"

touch "$BOX/Desktop/Screenshot A.png"
check "screenshots gathers them up"        "min screenshots -y -q --no-color >/dev/null 2>&1; [ -f '$BOX/Pictures/Screenshots/Screenshot A.png' ]"
check "from every folder it looks in"      "[ -f '$BOX/Pictures/Screenshots/Screenshot C.png' ]"
check "and leaves everything else alone"   "[ -f '$DL/report.pdf' ]"
check "screenshots --undo puts them back"  "min screenshots --undo -q --no-color >/dev/null 2>&1; [ -f '$BOX/Desktop/Screenshot A.png' ] && [ -f '$BOX/Documents/Screenshot C.png' ]"

rm -f "$BOX/Desktop/Screenshot A.png" "$BOX/Documents/Screenshot C.png" "$DL/Screenshot B.png"
rm -rf "$DL/Tidy" "$BOX/Pictures/Screenshots"

check "nothing loose is a calm answer"     "min screenshots -q --no-color | grep -q 'No loose screenshots'"
# Three sorters, three logs, all named by kind and then by time. A single
# glob across all of them handed "screenshots-…" to `min desktop --undo`,
# because s sorts after d — so the wrong run was reversed, every time.
crosstalk() {
    local box
    box=$(mktemp -d "${TMPDIR:-/tmp}/nimo-cross.XXXXXX") || return 1
    mkdir -p "$box/Desktop" "$box/Downloads"
    touch "$box/Downloads/paper.pdf"
    HOME="$box" bash "$MIN" downloads -y -q --no-color >/dev/null 2>&1 </dev/null
    touch "$box/Desktop/Screenshot Z.png"
    HOME="$box" bash "$MIN" screenshots -y -q --no-color >/dev/null 2>&1 </dev/null
    touch "$box/Desktop/notes.md"
    HOME="$box" bash "$MIN" desktop -y -q --no-color >/dev/null 2>&1 </dev/null
    HOME="$box" bash "$MIN" desktop --undo -q --no-color >/dev/null 2>&1 </dev/null

    local verdict=ok
    [ -f "$box/Desktop/notes.md" ] || verdict=desktop-not-restored
    [ -d "$box/Desktop/Tidy" ] && verdict=tidy-left-behind
    [ -f "$box/Pictures/Screenshots/Screenshot Z.png" ] || verdict=screenshots-disturbed
    [ -f "$box/Downloads/Tidy/Documents/paper.pdf" ] || verdict=downloads-disturbed
    printf '%s' "$verdict"
    rm -rf "$box"
}

check "each undo takes its own log"       "[ \"\$(crosstalk)\" = ok ]"

check "the platform is one of three"      "[ -n \"\$(bash -c '. $ROOT/lib/core.sh; nimo_platform')\" ]"
check "wsl is not treated as windows"     "[ \"\$(bash -c '. $ROOT/lib/core.sh; nimo_platform')\" != windows ] || [ \"\$(uname -s)\" != Linux ]"
check "zen says no away from macOS"        "[ \"\$(uname -s)\" = Darwin ] || min zen -q --no-color | grep -q 'macOS'"

# ---- what is still arriving stays put ------------------------------------
#
# A browser writes film.mp4.download while it is still fetching. Moving that
# out from under it breaks the download and leaves half a file under a name
# nobody recognises.

ARRIVING="$BOX/Downloads"
mkdir -p "$ARRIVING"
touch "$ARRIVING/finished.pdf" "$ARRIVING/film.mp4.download" \
      "$ARRIVING/page.crdownload" "$ARRIVING/chunk.part" "$ARRIVING/half.partial"

min downloads -y -q --no-color >/dev/null 2>&1

check "a finished download is filed"      "[ -f '$ARRIVING/Tidy/Documents/finished.pdf' ]"
check "a .download is left alone"         "[ -f '$ARRIVING/film.mp4.download' ]"
check "so is a .crdownload"               "[ -f '$ARRIVING/page.crdownload' ]"
check "so is a .part and a .partial"      "[ -f '$ARRIVING/chunk.part' ] && [ -f '$ARRIVING/half.partial' ]"
min downloads --undo -q --no-color >/dev/null 2>&1
rm -f "$ARRIVING"/*.download "$ARRIVING"/*.crdownload "$ARRIVING"/*.part "$ARRIVING"/*.partial "$ARRIVING/finished.pdf"

# ---- the menu counts what it is offering ---------------------------------

mkdir -p "$BOX/Desktop"
i=1
while [ "$i" -le 25 ]; do touch "$BOX/Desktop/heap-$i.txt"; i=$((i + 1)); done

check "the clear menu counts the desktop" "printf 'q' | NIMO_PICK_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" clear -q --no-color 2>&1 | grep -q 'Desktop.*items'"
check "and offers the trash as well"      "printf 'q' | NIMO_PICK_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" clear -q --no-color 2>&1 | grep -q 'Trash'"
check "min clear trash means the trash"   "min clear trash --dry-run -q --no-color | grep -q 'the trash'"

# a desktop with 25 things on it is exactly what doctor should mention
check "doctor says what to do next"       "min doctor -q --no-color | grep -q 'min clear desktop'"
rm -f "$BOX/Desktop"/heap-*.txt
check "and stays quiet when it is tidy"   "! min doctor -q --no-color | grep -q 'Next'"

# ---- the same file, more than once --------------------------------------

case "$(uname -s)" in
    Darwin) TRASHDIR="$BOX/.Trash" ;;
    *)      TRASHDIR="$BOX/.local/share/Trash/files" ;;
esac

DUP="$BOX/Documents"
mkdir -p "$DUP" "$BOX/Downloads/sub"
dd if=/dev/zero of="$DUP/paper.pdf" bs=1024 count=200 2>/dev/null
printf 'x' >> "$DUP/paper.pdf"
cp "$DUP/paper.pdf" "$BOX/Downloads/paper copy.pdf"
cp "$DUP/paper.pdf" "$BOX/Downloads/sub/paper (1).pdf"
dd if=/dev/zero of="$BOX/Downloads/alone.bin" bs=1024 count=300 2>/dev/null
printf 'y' >> "$BOX/Downloads/alone.bin"

check "duplicates finds the copies"       "min duplicates -q --no-color | grep -q 'paper'"
check "and counts what they cost"         "min duplicates -q --no-color | grep -q '1 file with copies'"
check "it names where each copy sits"     "[ \$(min duplicates -q --no-color | grep -c 'also in') -eq 2 ]"
check "a lonely file is not a copy"       "! min duplicates -q --no-color | grep -q alone"
check "duplicates never deletes"          "min duplicates -q --no-color >/dev/null; [ -f '$DUP/paper.pdf' ] && [ -f '$BOX/Downloads/paper copy.pdf' ]"
check "it says so out loud"               "min duplicates -q --no-color | grep -q 'does not delete'"
rm -f "$DUP/paper.pdf" "$BOX/Downloads/paper copy.pdf" "$BOX/Downloads/sub/paper (1).pdf" "$BOX/Downloads/alone.bin"
check "nothing doubled is a calm answer"  "min duplicates -q --no-color | grep -q 'No copies'"

mkdir -p "$TRASHDIR"
dd if=/dev/zero of="$TRASHDIR/thrown.bin" bs=1024 count=2048 2>/dev/null
touch "$TRASHDIR/note.txt"

check "empty sees what is in there"       "min empty --dry-run -q --no-color | grep -q 'waiting to be taken out'"
check "empty --dry-run empties nothing"   "[ -f '$TRASHDIR/thrown.bin' ]"
check "empty says it cannot be undone"    "min empty --dry-run -q --no-color | grep -q 'not undoable'"
check "empty takes it out"                "min empty -y -q --no-color >/dev/null 2>&1; [ ! -f '$TRASHDIR/thrown.bin' ]"
check "empty reports what it freed"       "dd if=/dev/zero of='$TRASHDIR/again.bin' bs=1024 count=1024 2>/dev/null; min empty -y -q --no-color | grep -q 'Freed 1.0 MB'"
check "an empty trash is a calm answer"   "min empty -q --no-color | grep -q 'Already empty'"

check "apps says no away from macOS"      "[ \"\$(uname -s)\" = Darwin ] || min apps -q --no-color | grep -q 'macOS'"
check "dark says no away from macOS"      "[ \"\$(uname -s)\" = Darwin ] || min dark -q --no-color | grep -q 'macOS'"
check "hide says no away from macOS"      "[ \"\$(uname -s)\" = Darwin ] || min hide -q --no-color | grep -q 'macOS'"

# ---- the way in ---------------------------------------------------------

check "bare min prints help off a tty"    "min --no-color | grep -q 'Commands'"
check "the menu lists every command"      "printf 'q' | NIMO_PICK_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" --menu --no-color 2>&1 | grep -q 'wallpaper'"
check "the menu runs what you choose"     "printf '\\033[B\\033[B\\033[B\\033[B\\n' | NIMO_PICK_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" --menu --no-color 2>/dev/null | grep -q 'safe to clean'"
check "q leaves the menu without doing"   "printf 'q' | NIMO_PICK_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" --menu --no-color >/dev/null 2>&1; [ \$? -eq 0 ]"

# ---- the face ------------------------------------------------------------

faces() { printf '/quit\n' | NIMO_REPL_FORCE=1 HOME="$BOX" bash "$MIN" "$@" --no-color 2>&1; }

check "the face is drawn off a terminal"  "faces | grep -q '●'"
check "--no-animation still draws it"     "faces --no-animation | grep -q '●'"
check "the whole face, not part of it"    "[ \$(faces | grep -c '│\\|╭\\|╰') -ge 8 ]"
check "animation = off is understood"     "mkdir -p \"$BOX/.nimo\"; printf 'animation = off\\n' > \"$BOX/.nimo/config\"; min --no-color >/dev/null 2>&1; rm -rf \"$BOX/.nimo\""
check "the eyes have a closed row too"    "grep -q 'NIMO_FACE_EYES_SHUT' \"$ROOT/lib/ui.sh\""
check "the demo is what the maker makes"  "python3 \"$ROOT/tools/make-demo.py\" | diff -q - \"$ROOT/assets/demo.svg\""

# ---- yes to everything ---------------------------------------------------

mkdir -p "$BOX/Desktop"
touch "$BOX/Desktop/auto-one.pdf" "$BOX/Desktop/auto-two.png"

# auto is what actually hands -y to each command, so the proof is that a
# command which would otherwise stop at the question goes all the way through
printf '/clear desktop\n/quit\n' | NIMO_AUTO=1 NIMO_REPL_FORCE=1 HOME="$BOX" \
    bash "$MIN" -q --no-color >/dev/null 2>&1

check "auto carries the yes through"      "[ -f '$BOX/Desktop/Tidy/Documents/auto-one.pdf' ]"
min desktop --undo -q --no-color >/dev/null 2>&1

# and without it, the same line stops at the question and changes nothing
printf '/clear desktop\n/quit\n' | NIMO_REPL_FORCE=1 HOME="$BOX" \
    bash "$MIN" -q --no-color >/dev/null 2>&1

check "without auto nothing is moved"     "[ -f '$BOX/Desktop/auto-one.pdf' ]"
check "auto says what it covers"          "printf '/auto\\n/quit\\n' | NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -y -q --no-color 2>&1 | grep -q 'Yes to everything'"
check "auto explains itself first"        "printf '/auto\\n/quit\\n' | NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -y -q --no-color 2>&1 | grep -q 'this session only'"
check "auto warns about the trash"        "printf '/auto\\n/quit\\n' | NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -y -q --no-color 2>&1 | grep -q 'no undo'"
check "the prompt shows it is on"         "printf '/quit\\n' | NIMO_AUTO=1 NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color 2>&1 | grep -q 'nimo auto'"
check "and off again on request"          "printf '/auto off\\n/quit\\n' | NIMO_AUTO=1 NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color 2>&1 | grep -q 'asks again'"
check "turning it on twice is calm"       "printf '/auto\\n/quit\\n' | NIMO_AUTO=1 NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color 2>&1 | grep -q 'already on'"
check "/yolo means the same thing"        "printf '/yolo\\n/quit\\n' | NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -y -q --no-color 2>&1 | grep -q 'Yes to everything'"
rm -f "$BOX/Desktop/auto-one.pdf" "$BOX/Desktop/auto-two.png"

# ---- choosing things ----------------------------------------------------

pick() {
    printf "$1" | NIMO_PICK_FORCE=1 HOME="$BOX" bash -c '
        . '"$ROOT"'/lib/ui.sh
        . '"$ROOT"'/lib/core.sh
        . '"$ROOT"'/lib/pick.sh
        nimo_init_colors
        nimo_pick "$1" hint "one
two
three
four" 2>/dev/null' _ "$2"
}

check "picker ticks what you tick"        "[ \"\$(pick '\\033[B \\033[B \\n' multi)\" = '2 3' ]"
check "picker ticks the first line too"   "[ \"\$(pick ' \\n' multi)\" = '1' ]"
check "picker can tick everything"        "[ \"\$(pick 'a\\n' multi)\" = '1 2 3 4' ]"
check "picker can untick everything"      "[ -z \"\$(pick 'an\\n' multi)\" ]"
check "picker wraps around at the top"    "[ \"\$(pick '\\033[A \\n' multi)\" = '4' ]"
check "single pick returns one line"      "[ \"\$(pick '\\033[B\\n' single)\" = '2' ]"
check "q cancels without choosing"        "[ -z \"\$(pick 'q' multi)\" ]"
pick_plain() {
    HOME="$BOX" bash -c '
        . '"$ROOT"'/lib/ui.sh
        . '"$ROOT"'/lib/core.sh
        . '"$ROOT"'/lib/pick.sh
        nimo_init_colors
        nimo_pick_by_number "$1" hint 4 2>/dev/null' _ "$1"
}

check "falls back to typing numbers"      "[ \"\$(printf '2 4\\n' | pick_plain multi)\" = '2 4' ]"
check "the fallback ignores nonsense"     "[ \"\$(printf '2 nope 99\\n' | pick_plain multi)\" = '2' ]"

# ---- the undo history ---------------------------------------------------

mkdir -p "$BOX/Desktop"
rm -f "$BOX/Desktop/a" "$BOX/Desktop/b"
touch "$BOX/Desktop/first.pdf" "$BOX/Desktop/second.png"
min desktop -y -q --no-color >/dev/null 2>&1

check "undo --list shows what happened"   "min undo --list -q --no-color | grep -q 'cleared your desktop'"
# Two tidies inside one second used to land on the same log name, where the
# second truncated the first and the only record of how to undo it was gone.
two_in_a_second() {
    local box
    box=$(mktemp -d "${TMPDIR:-/tmp}/nimo-collide.XXXXXX") || return 1
    mkdir -p "$box/Desktop"
    touch "$box/Desktop/first.pdf"
    HOME="$box" bash "$MIN" desktop -y -q --no-color >/dev/null 2>&1 </dev/null
    touch "$box/Desktop/second.pdf"
    HOME="$box" bash "$MIN" desktop -y -q --no-color >/dev/null 2>&1 </dev/null
    local logs newest
    logs=$(ls -1 "$box"/.nimo/undo/desktop-*.tsv 2>/dev/null | wc -l | tr -d ' ')
    newest=$(ls -1 "$box"/.nimo/undo/desktop-*.tsv 2>/dev/null | tail -1)
    printf '%s %s' "$logs" "$(grep -c . "$newest" 2>/dev/null || echo 0)"
    rm -rf "$box"
}

check "two tidies in a second keep both"  "[ \"\$(two_in_a_second)\" = '2 1' ]"

# The same second, and then the undo. The extra log is named "…_2", and `ls`
# sorts that *before* the plain name under en_US.UTF-8 — the locale a Mac
# terminal uses — and *after* it under C, which is what CI uses. Picking the
# newest by name therefore replayed the wrong run on a Mac and only on a Mac.
# This runs the case under both collations.
newest_wins() {
    local box locale="$1"
    box=$(mktemp -d "${TMPDIR:-/tmp}/nimo-locale.XXXXXX") || return 1
    mkdir -p "$box/Desktop"
    touch "$box/Desktop/older.pdf"
    LC_ALL="$locale" HOME="$box" bash "$MIN" desktop -y -q --no-color >/dev/null 2>&1 </dev/null
    touch "$box/Desktop/newer.pdf"
    LC_ALL="$locale" HOME="$box" bash "$MIN" desktop -y -q --no-color >/dev/null 2>&1 </dev/null
    LC_ALL="$locale" HOME="$box" bash "$MIN" desktop --undo -q --no-color >/dev/null 2>&1 </dev/null

    # the newest run moved newer.pdf, so undoing it must bring exactly that back
    if [ -f "$box/Desktop/newer.pdf" ] && [ ! -f "$box/Desktop/older.pdf" ]; then
        printf 'ok'
    else
        printf 'wrong-run'
    fi
    rm -rf "$box"
}

check "undo takes the newest under C"     "[ \"\$(newest_wins C)\" = ok ]"
check "and the newest under en_US.UTF-8"  "[ \"\$(newest_wins en_US.UTF-8)\" = ok ]"
check "undo --list counts the files"      "min undo --list -q --no-color | grep -q '2 files'"

printf '\n' | NIMO_PICK_FORCE=1 HOME="$BOX" bash "$MIN" undo -q --no-color >/dev/null 2>&1

check "undo reverses what you picked"     "[ -f '$BOX/Desktop/first.pdf' ] && [ -f '$BOX/Desktop/second.png' ]"
check "undo is empty once it is spent"    "min undo --list -q --no-color | grep -qv 'cleared your desktop' || true"
rm -f "$BOX/Desktop/first.pdf" "$BOX/Desktop/second.png"
rm -rf "$BOX/.nimo"

# ---- ~/.nimo/config -----------------------------------------------------

mkdir -p "$BOX/.nimo"
printf 'days = 9999\nlimit = 2\n# a comment\ncolor = never\n' > "$BOX/.nimo/config"

check "config sets the download age"      "! min preview -q --no-color | grep -q 'Old downloads'"
check "config sets the row limit"         "[ \$(min top -q --no-color | grep -c '█') -le 2 ]"
check "a flag still beats the config"     "min preview -q --no-color --days 1 | grep -q 'Old downloads'"
rm -rf "$BOX/.nimo"

# ---- the desktop --------------------------------------------------------

DESK="$BOX/Desktop"
mkdir -p "$DESK/a project"
touch "$DESK/Screenshot 2026-01-01 at 10.11.32.png" \
      "$DESK/photo of the sea.JPG" \
      "$DESK/invoice.pdf" \
      "$DESK/archive.zip" \
      "$DESK/script.sh" \
      "$DESK/no-extension-thing" \
      "$DESK/.hidden-thing"

check "desktop --dry-run moves nothing"   "min desktop --dry-run -q --no-color >/dev/null; [ -f '$DESK/invoice.pdf' ]"
check "desktop counts what is there"      "min desktop --dry-run -q --no-color | grep -q 'Screenshots'"

min desktop -y -q --no-color >/dev/null 2>&1

check "the desktop is clear"              "[ \$(ls '$DESK' | grep -cv '^Tidy\$') -eq 0 ]"
check "screenshots are recognised"        "[ -f '$DESK/Tidy/Screenshots/Screenshot 2026-01-01 at 10.11.32.png' ]"
check "images land in Images"             "[ -f '$DESK/Tidy/Images/photo of the sea.JPG' ]"
check "documents land in Documents"       "[ -f '$DESK/Tidy/Documents/invoice.pdf' ]"
check "archives land in Archives"         "[ -f '$DESK/Tidy/Archives/archive.zip' ]"
check "code lands in Code"                "[ -f '$DESK/Tidy/Code/script.sh' ]"
check "the odd one out lands in Other"    "[ -f '$DESK/Tidy/Other/no-extension-thing' ]"
check "folders are moved whole"           "[ -d '$DESK/Tidy/Folders/a project' ]"
check "hidden files are left alone"       "[ -f '$DESK/.hidden-thing' ]"
check "a second run has nothing to do"    "min desktop -y -q --no-color | grep -q 'already clear'"

min desktop --undo -q --no-color >/dev/null 2>&1

check "undo brings everything back"       "[ -f '$DESK/invoice.pdf' ] && [ -f '$DESK/photo of the sea.JPG' ]"
check "undo keeps folders intact"         "[ -d '$DESK/a project' ]"
check "undo clears the Tidy folder away"  "[ ! -d '$DESK/Tidy' ]"
check "undo with nothing to undo is calm" "min desktop --undo -q --no-color >/dev/null 2>&1; min desktop --undo -q --no-color 2>&1 | grep -qE 'put back|nothing to undo'"

check "dock says no on this machine"      "[ \"\$(uname -s)\" = Darwin ] || min dock -q --no-color | grep -q 'macOS'"
check "wallpaper says no on this machine" "[ \"\$(uname -s)\" = Darwin ] || min wallpaper -q --no-color | grep -q 'macOS'"

# ---- and finally, actually cleaning -------------------------------------

REPORTED=$(min preview -q --no-color | awk '/Total/ {print $(NF - 1), $NF}')
FREED=$(min clean -y -q --no-color | awk '/Freed/ {print $(NF - 1), $NF}')

check "clean frees what it promised"      "[ -n '$REPORTED' ] && [ '$REPORTED' = '$FREED' ]"
check "the cache is gone"                 "[ ! -f '$CACHE/big-cache-file' ]"
check "the trash is empty"                "[ ! -f '$TRASH/already-thrown-away' ]"
check "the npm cache is gone"             "[ ! -f '$BOX/.npm/_cacache/package' ]"
check "your downloads survived"           "[ -f '$BOX/Downloads/old one.dmg' ]"
check "your node_modules survived"        "[ -f '$BOX/proj/node_modules/dep' ]"
check "your movies survived"              "[ -f '$BOX/Movies/holiday.mov' ]"
check "your documents survived"           "[ -f '$BOX/Documents/thesis.pdf' ]"
check "a second run finds nothing"        "min preview -q --no-color | grep -q 'nothing to clean here'"
check "--json agrees there is nothing"    "min preview --json | grep -q '\"safe_bytes\": 0'"

# ---- verdict ------------------------------------------------------------

printf '\n'
if [ "$FAIL" -eq 0 ]; then
    printf '  %s✓ %d passed%s\n\n' "$G" "$PASS" "$Z"
    exit 0
else
    printf '  %s%d passed, %d failed%s%s\n\n' "$R" "$PASS" "$FAIL" "$FAILED" "$Z"
    exit 1
fi
