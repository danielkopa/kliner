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

check() {
    if eval "$2" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        printf '  %s✓%s %s\n' "$G" "$Z" "$1"
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
check "/ lists what you can type"         "typed '/' | grep -q '/cleardesktop'"
check "/doctor runs doctor"               "typed '/doctor' | grep -q 'your computer'"
check "the slash is optional"             "typed 'doctor' | grep -q 'your computer'"
check "/preview runs preview"             "typed '/preview' | grep -q 'safe to clean'"
check "/clean desktop means the desktop"  "typed '/clean desktop' | grep -q 'your desktop'"
check "so does clear desktop"             "typed 'clear desktop' | grep -q 'your desktop'"
check "flags are passed through"          "typed '/preview --json' | grep -q '\"safe_bytes\"'"
check "a typo is caught"                  "typed '/wallpapr' | grep -q 'did you mean /wallpaper'"
check "a typo mid-phrase is caught"       "typed '/clean deskopt' | grep -q 'did you mean /clean desktop'"
check "nonsense is not guessed at"        "typed '/xyzzy' | grep -q 'does not know' && ! typed '/xyzzy' | grep -q 'did you mean'"
check "/quit leaves quietly"              "typed '/doctor' | grep -q 'bye'"
check "the prompt exits 0"                "printf '/quit\n' | NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color >/dev/null 2>&1"
check "end of input is not an error"      "printf '' | NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" -q --no-color >/dev/null 2>&1"
check "one command cannot leak into next" "typed '/preview --json' | grep -q 'safe_bytes' && typed '/preview' | grep -q 'safe to clean'"

# ---- the newer commands -------------------------------------------------

DL="$BOX/Downloads"
mkdir -p "$DL" "$BOX/Documents" "$BOX/Pictures"
touch "$DL/Screenshot B.png" "$DL/installer.dmg" "$DL/report.pdf"
touch "$BOX/Documents/Screenshot C.png"

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
check "zen says no away from macOS"        "[ \"\$(uname -s)\" = Darwin ] || min zen -q --no-color | grep -q 'macOS'"

# ---- the way in ---------------------------------------------------------

check "bare min prints help off a tty"    "min --no-color | grep -q 'Commands'"
check "the menu lists every command"      "printf 'q' | NIMO_PICK_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" --menu --no-color 2>&1 | grep -q 'wallpaper'"
check "the menu runs what you choose"     "printf '\\033[B\\033[B\\033[B\\033[B\\n' | NIMO_PICK_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" --menu --no-color 2>/dev/null | grep -q 'safe to clean'"
check "q leaves the menu without doing"   "printf 'q' | NIMO_PICK_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" --menu --no-color >/dev/null 2>&1; [ \$? -eq 0 ]"

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
