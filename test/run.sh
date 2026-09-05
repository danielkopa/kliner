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

# ---- and the ways around it ---------------------------------------------
#
# The guard used to compare the path it was handed against $HOME as text. A
# glob does not know that "$HOME/." is $HOME, so that spelling read as
# "somewhere under your home" and passed — and what runs next deletes every
# child of what it is given. That is the home folder, emptied, by the one
# command whose whole promise is that it will not.
#
# Each of these is a spelling of the same folder. Every one of them has to be
# refused, and the ordinary path underneath still has to be allowed, or the
# guard has simply been turned off.

guard() { HOME="$1" bash -c '. '"$ROOT"'/lib/ui.sh; . '"$ROOT"'/lib/core.sh; nimo_is_protected "$1"' _ "$2"; }

check "a dot does not open your home"     "guard '$BOX' '$BOX/.'"
check "nor a dot and a slash"             "guard '$BOX' '$BOX/./'"
check "nor two slashes"                   "guard '$BOX' '$BOX//'"
check "nor a trailing slash"              "guard '$BOX' '$BOX/'"
check "nor a dot in the middle"           "guard '$BOX' '$BOX/./Library/../..'"
check "the cache under it is still fine"  "! guard '$BOX' '$BOX/Library/Caches'"
check "even spelled with a dot"           "! guard '$BOX' '$BOX/./Library/Caches'"

# With HOME empty, "$HOME"/* is /* — which matches every absolute path there
# is, and the guard said yes to all of them.
check "an empty HOME protects everything" "guard '' /home/someone/Documents"
check "so does a HOME of just a slash"    "guard / /home/someone/Documents"
check "and one that is not a path at all" "guard nonsense /home/someone/Documents"

# `find dir/ -mindepth 1` follows a link the moment the path ends in a slash,
# and a cache folder moved to another disk is exactly that link.
OUT="$BOX/../nimo-outside.$$"
mkdir -p "$OUT" "$BOX/Library" && printf 'do not delete me\n' > "$OUT/important.txt"
ln -s "$OUT" "$BOX/Library/linked-cache" 2>/dev/null

purge() { HOME="$BOX" bash -c '. '"$ROOT"'/lib/ui.sh; . '"$ROOT"'/lib/core.sh; nimo_init_colors; nimo_purge_children "$1"' _ "$1" 2>&1; }

check "it will not clean through a link"  "purge '$BOX/Library/linked-cache' | grep -q 'link'"
check "and the file behind it survives"   "[ -f '$OUT/important.txt' ]"
check "even asked with a trailing slash"  "purge '$BOX/Library/linked-cache/' >/dev/null 2>&1; [ -f '$OUT/important.txt' ]"

printf 'mine\n' > "$BOX/precious.txt"
check "and it will not empty your home"   "purge '$BOX/.' >/dev/null 2>&1; [ -f '$BOX/precious.txt' ]"
check "nor with two slashes"              "purge '$BOX//' >/dev/null 2>&1; [ -f '$BOX/precious.txt' ]"
check "nor by saying so plainly"          "purge '$BOX' >/dev/null 2>&1; [ -f '$BOX/precious.txt' ]"

# min blank checks the name you typed and truncates what it points at
ln -s "$OUT/important.txt" "$BOX/looks-like-a-file.txt" 2>/dev/null
check "blank will not follow a link"      "HOME='$BOX' bash '$MIN' blank '$BOX/looks-like-a-file.txt' -y -q --no-color 2>&1 | grep -q 'link'"
check "and what it pointed at is intact"  "[ -s '$OUT/important.txt' ]"

rm -f "$BOX/looks-like-a-file.txt" "$BOX/Library/linked-cache"
rm -rf "$OUT"
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
check "the short list stays short"         "[ \$(typed '/' | grep -c '^     /') -le 8 ]"

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

# ---- it has to finish -----------------------------------------------------
#
# The sorter used to be a loop over buckets around a loop over items, with a
# fork inside both — so the work grew with buckets times files, and a folder
# of two thousand downloads took half a minute to *preview*. Nobody waits that
# long; they decide the tool is broken.
#
# The number below is a cliff, not a target: this finishes in about a second,
# and it is here to catch the shape of that bug coming back, not to police a
# few hundred milliseconds on a busy machine.

MANY="$BOX/many"
mkdir -p "$MANY/Downloads"
i=0
while [ "$i" -lt 400 ]; do : > "$MANY/Downloads/file$i.pdf"; i=$((i + 1)); done

many_secs() {
    local a b
    a=$(date +%s)
    HOME="$MANY" bash "$MIN" downloads --dry-run -q --no-color </dev/null >/dev/null 2>&1
    b=$(date +%s)
    printf '%s' "$((b - a))"
}

check "400 downloads preview in seconds" "[ \"$(many_secs)\" -lt 15 ]"
check "and it counted all of them"       "HOME=\"$MANY\" bash \"$MIN\" downloads --dry-run -q --no-color </dev/null | grep -q '400 items'"
check "the classifier forks per file 0x" "! grep -q 'basename \"\$path\"\|\$(nimo_bucket_of' \"$ROOT/lib/desktop.sh\""
rm -rf "$MANY"

# ---- names people actually have -------------------------------------------
#
# A file name is not a word. It can hold a quote, an apostrophe, a backslash,
# a leading dash, a glob character, a command substitution, a semicolon, a
# pipe, 180 characters, or an emoji — and every one of those has, somewhere,
# been the bug that deleted the wrong thing or ran the wrong command.
#
# nimo moves all of them and executes none of them. The two it cannot move are
# the two it cannot write down: a newline or a tab in the name, because the
# undo log is one line per move and a name with a newline in it is not one
# line. Those it names and leaves alone, rather than sorting fewer things than
# are in the folder and saying nothing.

NASTY="$BOX/nasty"
mkdir -p "$NASTY/Desktop"
python3 - "$NASTY/Desktop" <<'MAKE'
import os, sys
d = sys.argv[1]
for n in ["spaces in name.txt", "it's an apostrophe.pdf", 'double"quote.txt',
          "back\\slash.txt", "-rf.txt", "--help.pdf", "unicode ✨.png",
          "$(whoami).txt", "`id`.txt", "semi;colon.txt", "pipe|char.txt",
          "star*.txt", "quest?.txt", "[bracket].txt", "x" * 180 + ".txt",
          "new\nline.txt", "tab\there.txt"]:
    try:
        open(os.path.join(d, n), "w").close()
    except OSError:
        pass
MAKE

nasty() { HOME="$NASTY" bash "$MIN" "$@" </dev/null 2>&1; }

check "it counts only what it can move"   "nasty desktop --dry-run -q --no-color | grep -q '15 items'"
check "and names the two it cannot"       "nasty desktop --dry-run -q --no-color | grep -q 'newline or a tab'"
check "nothing in a name is ever run"     "! nasty desktop --dry-run -q --no-color | grep -q 'root\|uid='"

nasty desktop -y -q --no-color >/dev/null 2>&1
check "all fifteen are filed"             "[ \$(find \"$NASTY/Desktop/Tidy\" -type f | wc -l) = 15 ]"
check "nothing failed to move"            "! nasty desktop -y -q --no-color | grep -q 'could not be moved'"
check "the quote one is there"            "[ -f \"$NASTY/Desktop/Tidy/Documents/double\\\"quote.txt\" ]"
check "and the one starting with a dash"  "[ -f \"$NASTY/Desktop/Tidy/Documents/-rf.txt\" ]"
check "and the command substitution one"  "[ -f \"$NASTY/Desktop/Tidy/Documents/\\\$(whoami).txt\" ]"
# counted through -print0, because a name with a newline in it is two lines
# to `find` and one file to everything else — which is the whole point here
nfiles() { find "$1" -maxdepth 1 -type f -print0 2>/dev/null | tr -dc '\0' | wc -c | tr -d ' '; }

check "the awkward two stayed put"        "[ \"\$(nfiles \"$NASTY/Desktop\")\" = 2 ]"

nasty desktop --undo -q --no-color >/dev/null 2>&1
check "and undo brings all fifteen back"  "[ \"\$(nfiles \"$NASTY/Desktop\")\" = 17 ]"
check "the log has one line per move"     "[ \$(cat \"$NASTY/.nimo/undo\"/desktop-*.tsv | wc -l) = 15 ]"
rm -rf "$NASTY"

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

# ---- three ways to sort --------------------------------------------------

SORT="$BOX/Desktop"
mkdir -p "$SORT"
touch "$SORT/apple.pdf" "$SORT/avocado.txt" "$SORT/banana.png" "$SORT/9lives.zip"
touch -t 202601150000 "$SORT/apple.pdf" 2>/dev/null || true

check "by kind is what it does by default" "min desktop --dry-run -q --no-color | grep -q 'Documents'"
check "by letter groups on the first one"  "min desktop --by letter --dry-run -q --no-color | grep -q '^     A '"
check "and a digit is not a letter"        "min desktop --by letter --dry-run -q --no-color | grep -q '^     # '"
check "by date groups on the month"        "min desktop --by date --dry-run -q --no-color | grep -qE '^     [0-9]{4}-[0-9]{2} '"
check "--by says so in the summary"        "min desktop --by letter --dry-run -q --no-color | grep -q '<letter>'"
check "--by refuses what it cannot do"     "min desktop --by colour >/dev/null 2>&1; [ \$? -eq 2 ]"

min desktop --by letter -y -q --no-color >/dev/null 2>&1
check "by letter files them under A"       "[ -f '$SORT/Tidy/A/apple.pdf' ] && [ -f '$SORT/Tidy/A/avocado.txt' ]"
check "and under B"                        "[ -f '$SORT/Tidy/B/banana.png' ]"
check "and the odd one under #"            "[ -f '$SORT/Tidy/#/9lives.zip' ]"
min desktop --undo -q --no-color >/dev/null 2>&1
check "undo does not care how you sorted"  "[ -f '$SORT/apple.pdf' ] && [ ! -d '$SORT/Tidy' ]"
rm -f "$SORT/apple.pdf" "$SORT/avocado.txt" "$SORT/banana.png" "$SORT/9lives.zip"

# ---- emptying a file, and getting it back --------------------------------

mkdir -p "$BOX/Documents"
printf 'the quick brown fox\njumped over it\n' > "$BOX/Documents/notes.txt"

check "blank needs to know which file"    "! min blank -q --no-color >/dev/null 2>&1"
check "blank refuses a folder"            "min blank '$BOX/Documents' -q --no-color 2>&1 | grep -q 'is a folder'"
check "blank refuses outside your home"   "min blank /etc/hosts -q --no-color 2>&1 | grep -q 'outside your home'"
NOTE_BYTES=$(wc -c < "$BOX/Documents/notes.txt" | tr -d ' ')

# a relative path is how anyone would actually type this, and it was the one
# way the command could not be used: the home-folder guard compares against
# $HOME, and "Documents/notes.txt" never starts with it
check "blank takes a relative path"       "cd \"$BOX\" && min blank Documents/notes.txt --dry-run -q --no-color | grep -q 'notes.txt'"
check "blank takes ./ in front of it"     "cd \"$BOX\" && min blank ./Documents/notes.txt --dry-run -q --no-color | grep -q 'notes.txt'"
check "blank takes ~ as your home"        "cd / && min blank '~/Documents/notes.txt' --dry-run -q --no-color | grep -q 'notes.txt'"
check "blank takes the whole path"        "min blank '$BOX/Documents/notes.txt' --dry-run -q --no-color | grep -q 'notes.txt'"
check "and shows it relative to home"     "min blank '$BOX/Documents/notes.txt' --dry-run -q --no-color | grep -q ' Documents$'"

check "blank shows the size in bytes"     "min blank '$BOX/Documents/notes.txt' --dry-run -q --no-color | grep -q \"\$NOTE_BYTES B\""
check "--dry-run empties nothing"         "[ \$(wc -c < '$BOX/Documents/notes.txt') -eq \$NOTE_BYTES ]"

min blank "$BOX/Documents/notes.txt" -y -q --no-color >/dev/null 2>&1

check "blank empties the file"            "[ \$(wc -c < '$BOX/Documents/notes.txt') -eq 0 ]"
check "and the file is still there"       "[ -f '$BOX/Documents/notes.txt' ]"
check "and a copy was kept"               "ls '$BOX'/.nimo/undo/files/* >/dev/null 2>&1"
check "undo lists the emptied file"       "min undo --list -q --no-color | grep -q 'emptied a file'"
check "and lists it first, being newest"  "min undo --list -q --no-color | grep -m1 '^ *[0-9]' | grep -q 'emptied a file'"

printf '\n' | NIMO_PICK_FORCE=1 HOME="$BOX" bash "$MIN" undo -q --no-color >/dev/null 2>&1

check "undo puts the contents back"       "[ \$(wc -c < '$BOX/Documents/notes.txt') -eq \$NOTE_BYTES ]"
check "word for word"                     "grep -q 'quick brown fox' '$BOX/Documents/notes.txt'"
check "an empty file is a calm answer"    ": > '$BOX/Documents/notes.txt'; min blank '$BOX/Documents/notes.txt' -q --no-color | grep -q 'Already empty'"
rm -rf "$BOX/Documents/notes.txt" "$BOX/.nimo"

# nimo left this file empty. Anything in it now was put there since, and the
# kept copy going back over it destroys work with no second undo behind it.
mkdir -p "$BOX/Documents"
printf 'the original\n' > "$BOX/Documents/again.txt"
min blank "$BOX/Documents/again.txt" -y -q --no-color >/dev/null 2>&1
printf 'written afterwards\n' > "$BOX/Documents/again.txt"
min undo --all -y -q --no-color >/dev/null 2>&1
check "undo leaves a file written since alone" \
    "grep -q 'written afterwards' '$BOX/Documents/again.txt'"
check "and says so rather than saying nothing" \
    "grep -q 'has been written to since, left alone' '$ROOT/lib/blank.sh'"
rm -rf "$BOX/Documents/again.txt" "$BOX/.nimo"

# The log is one tab-separated line per file, so a name holding a tab splits
# it into fields nothing can read back: the copy is kept, the file is emptied,
# and undo can never find its way home.
TABBED="$BOX/Documents/od$(printf '\t')d.txt"
printf 'xy\n' > "$TABBED"
TABOUT=$(min blank "$TABBED" -y -q --no-color 2>&1)
check "blank refuses a name it cannot write down" \
    "printf '%s' \"\$TABOUT\" | grep -q 'cannot write that name down'"
check "and leaves that file exactly as it was" \
    "[ \$(wc -c < \"\$TABBED\") -eq 3 ]"
rm -f "$TABBED"

# A folder to sort into is a name, not a route. Spliced onto the desktop, a
# value with a separator in it sends every moved file outside the home folder.
check "the tidy folder cannot be a route"  \
    "grep -q \"''|\\*/\\*|\" '$ROOT/lib/core.sh'"
check "and reading is held inside home too" \
    "grep -q 'nimo_inside_home()' '$ROOT/lib/core.sh' && grep -q 'nimo_inside_home \"\$where\"' '$ROOT/lib/tools.sh'"

# min menu dispatched to a function defined further down the file, so it was
# not there yet and the command exited 127.
check "min menu is defined before it is dispatched to" \
    "awk '/^nimo_menu_then_run\\(\\)/{d=NR} /^if . -n ..NIMO_COMMAND/{u=NR} END{exit !(d && u && d < u)}' '$ROOT/min'"

# A preview changes nothing, and an empty log left in the backups folder is a
# change. min startup and min dock both got this right.
check "a setup preview leaves no log behind" \
    "grep -q 'NIMO_SETUP_LOG=\"\"' '$ROOT/lib/setup.sh'"

# This was the one place in nimo that deleted its own record of what it had
# done, which is the thing nimo says it never does.
check "the wallpaper record is spent, not deleted" \
    "grep -q 'nimo_undo_spend \"\$kept\"' '$ROOT/lib/wall.sh' && ! grep -q 'rm -f \"\$NIMO_BACKUP_DIR/wallpaper.txt\"' '$ROOT/lib/wall.sh'"

# A file that has been moved with nothing written down about where it went is
# a file nimo cannot put back. The record goes in first; if the move then does
# not happen, the record comes back out.
check "what nimo is about to move is written down before it moves" \
    "! grep -q 'mv \"\$what\" \"\$dest\" 2>/dev/null || return 1' '$ROOT/lib/startup.sh' \
     && ! grep -q 'mv \"\$src\" \"\$dest\" 2>/dev/null || continue' '$ROOT/lib/dock.sh'"
check "and taken back out if the move did not happen" \
    "grep -q 'nimo_undo_drop_last()' '$ROOT/lib/core.sh' \
     && [ \$(grep -c 'nimo_undo_drop_last \"' '$ROOT/lib/desktop.sh' '$ROOT/lib/dock.sh' '$ROOT/lib/startup.sh' | awk -F: '{t+=\$2} END{print t}') = 6 ]"

# One of the six rules the README stands on, and until now the one with no
# test under it — which is how `min update` came to be quietly running
# `git pull` for you.
check "nimo never reaches the network" \
    "! grep -rnE '(^|[ \t;&|(])(curl|wget|ping|nslookup|nc|scp|ftp) |git (pull|fetch|clone)' '$ROOT/lib' '$ROOT/min' \
     | grep -v printf | grep -qv '^[^:]*:[0-9]*: *#'"
check "and update says what to type instead of typing it" \
    "min update --no-color | grep -q 'git pull' && min update --no-color | grep -q 'never reaches the network'"

# doctor said 140 while the desktop showed 137 icons and clearing it moved
# 137: it was counting the dotfiles Finder hides and the folder nimo itself
# had made to tidy into. A count nobody can reproduce by looking is worse
# than no count.
check "doctor counts what you can see, not what is there" \
    "d=\$(mktemp -d) && mkdir -p \"\$d/Tidy\" && touch \"\$d/one\" \"\$d/two\" \"\$d/.quiet\" \
     && [ \"\$(bash -c '. \"$ROOT/lib/core.sh\" 2>/dev/null; nimo_count_dir_items \"\$0\"' \"\$d\")\" = 2 ]"

# SQLite's only escape inside a single-quoted string is a doubled quote. A
# picture called "Dan's holiday.jpg" would otherwise close the string in the
# middle of its own name and leave the rest to be read as SQL.
check "a wallpaper's name cannot end up being read as SQL" \
    "grep -q 'nimo_sql_quote()' '$ROOT/lib/wall.sh' \
     && ! grep -q \"set value = '\\\$pic'\" '$ROOT/lib/wall.sh' \
     && [ \$(grep -c 'nimo_sql_quote \"\$pic\"' '$ROOT/lib/wall.sh') = 3 ]"
check "and a quote in it is doubled, not dropped" \
    "[ \"\$(NIMO_LIB='$ROOT/lib' bash -c '. \"$ROOT/lib/wall.sh\" 2>/dev/null; nimo_sql_quote \"Dan'\"'\"'s photo.jpg\"')\" = \"Dan''s photo.jpg\" ]"

# -e is false for a symlink whose target is gone, and a broken symlink is
# still a name that is taken.
check "a broken link still counts as something there" \
    "grep -q '\\[ ! -L \"\$dir/\$name\" \\]' '$ROOT/lib/desktop.sh' && grep -q '\\[ -L \"\$try\" \\]' '$ROOT/lib/core.sh'"

check "dock --fast is a macOS thing"      "[ \"\$(uname -s)\" = Darwin ] || min dock --fast -q --no-color | grep -q 'macOS'"

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
check "and counts what they cost"         "min duplicates -q --no-color | grep -q 'kept more than once'"
check "it names every copy, with its path" "[ \$(min duplicates -q --no-color | grep -c '  also  ') -eq 2 ]"
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

# ---- nothing may drift ---------------------------------------------------
#
# Every command nimo can dispatch has to be findable: in `min help`, in the
# tab completions, in the manual, and by a word at the prompt. Documentation
# that drifts from the code is how a tool ends up with features nobody knows
# about — so this is a test rather than a good intention.

dispatchable() {
    sed -n '/^nimo_dispatch()/,/^}/p' "$ROOT/min" \
        | sed -n 's/^        \([a-z|]*\)).*/\1/p' \
        | tr '|' '\n' | grep -v '^$' | sort -u
}

missing_from() {
    local where="$1" name
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        grep -q -- "$name" "$where" || printf '%s ' "$name"
    done <<EOF
$(dispatchable)
EOF
}

check "there are commands to check"       "[ \$(dispatchable | wc -l) -ge 18 ]"
check "every command is in min help"      "[ -z \"\$(min help --no-color | { cat > '$BOX/help.txt'; }; missing_from '$BOX/help.txt')\" ]"
check "every command tab-completes"       "[ -z \"\$(missing_from '$ROOT/completions/min.bash')\" ]"
check "every command is in the manual"    "[ -z \"\$(missing_from '$ROOT/man/min.1')\" ]"
check "every command has a prompt word"   "[ -z \"\$(missing_from '$ROOT/lib/repl.sh')\" ]"
check "every command is in the readme"    "[ -z \"\$(missing_from '$ROOT/README.md')\" ]"

# The same rule for flags. `--color` was accepted by the parser and mentioned
# nowhere, which is the quiet half of drift: not a promise nimo breaks, a
# feature nobody can find.
flagged() {
    sed -n '/^while \[ \$# -gt 0 \]/,/^done/p' "$ROOT/min" \
        | sed -n 's/^        \(-[^)]*\)).*/\1/p' \
        | tr '|' '\n' | sed -e 's/=\*$//' \
        | grep '^--' | sort -u
}

flags_missing_from() {
    local where="$1" name
    # roff spells every dash \- , so the man page is read with the backslashes
    # taken out rather than with a second, cleverer pattern
    tr -d '\\' < "$where" > "$BOX/flat.txt"
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        grep -q -- "$name" "$BOX/flat.txt" || printf '%s ' "$name"
    done <<EOF
$(flagged)
EOF
}

check "there are flags to check"          "[ \$(flagged | wc -l) -ge 14 ]"
check "every flag is in min help"         "[ -z \"\$(flags_missing_from '$BOX/help.txt')\" ]"
check "every flag is in the manual"       "[ -z \"\$(flags_missing_from '$ROOT/man/min.1')\" ]"
check "every flag tab-completes"          "[ -z \"\$(flags_missing_from '$ROOT/completions/min.bash')\" ]"

# and the version has to agree with itself everywhere it is written down
check "the version agrees with itself"    "[ \"\$(tr -d ' \n' < '$ROOT/VERSION')\" = \"\$(min version | awk '{print \$2}')\" ]"
check "the changelog knows this version"  "grep -q \"^## \$(tr -d ' \n' < '$ROOT/VERSION')\" '$ROOT/CHANGELOG.md'"
check "the formula points at this tag"    "grep -q \"v\$(tr -d ' \n' < '$ROOT/VERSION')\.tar\.gz\" '$ROOT/Formula/nimo.rb'"

# The website is documentation too. It drifted eighteen versions once while
# nobody was looking at it, and a page that names a version it has never seen
# is worse than a page with no version on it at all.
check "the website knows this version"    "grep -q \"v\$(tr -d ' \n' < '$ROOT/VERSION')\" '$ROOT/docs/index.html'"

# ---- what starts when you sign in ---------------------------------------

check "startup says where it works"       "min startup --no-color 2>&1 | grep -q 'macOS and Windows'"
check "and changes nothing on linux"      "min startup -y --no-color >/dev/null 2>&1; [ ! -d \"$BOX/.nimo/backups/startup\" ]"
check "it never uninstalls anything"      "! grep -q 'msiexec\|rm -rf\|Uninstall-Package' '$ROOT/lib/startup.sh'"
check "and never touches HKLM"            "! grep -q 'reg_erase .*RUN_MACHINE\|reg_write .*RUN_MACHINE' '$ROOT/lib/startup.sh'"

# ---- it fits the window it is in ------------------------------------------
#
# 52 columns was a constant. That is fine on a full-width terminal and wrong
# on every other one — and half-width is exactly where this tool gets used,
# next to the desktop it is tidying. A panel wider than the window wraps every
# rule and every row, and a wrapped box reads as a broken one.
#
# Prose is allowed to wrap: prose reads fine wrapped, a table does not. So
# what is measured here is the frame and the rows — the parts where a wrapped
# line stops looking like a column of numbers.
#
# Counted in characters, by python. A box-drawing character is three bytes,
# and awk under the wrong locale will tell you a 55-column rule is 160 wide.

fits() {
    COLUMNS="$1" HOME="$BOX" bash "$MIN" "$2" -q --no-color </dev/null 2>&1 \
        | python3 -c '
import sys, re
cols = int(sys.argv[1])
worst = 0
for line in sys.stdin.read().splitlines():
    # the frame, and any row that ends in a measurement
    if re.match(r"^\s*[╭╰]", line) or re.search(r"\d\s*(B|KB|MB|GB|items?|files?)\s*$", line):
        worst = max(worst, len(line))
print(worst)
' "$1"
}

check "the frame fits 80 columns"         "[ \"\$(fits 80 preview)\" -le 80 ]"
check "and 60"                            "[ \"\$(fits 60 preview)\" -le 60 ]"
check "and 46"                            "[ \"\$(fits 46 preview)\" -le 46 ]"
check "and 38"                            "[ \"\$(fits 38 preview)\" -le 38 ]"
check "doctor fits a narrow window too"   "[ \"\$(fits 40 doctor)\" -le 40 ]"
check "and top"                           "[ \"\$(fits 40 top)\" -le 40 ]"
check "a wide one does not sprawl"        "[ \"\$(fits 200 preview)\" -le 56 ]"

# The note on the end of a row is the part a narrow window loses: the label
# and the number are the data, and a wrapped note turns a column of numbers
# into a paragraph. The question is how wide the window is, not the panel — a
# 52-column panel still writes a 68-column line once a note is on the end.
mkdir -p "$BOX/.cache/something"
dd if=/dev/zero of="$BOX/.cache/something/blob" bs=1024 count=2048 2>/dev/null

check "a wide window keeps the notes"     "COLUMNS=80 min preview --no-color | grep -q 'rebuilt'"
check "a narrow one drops them"           "! COLUMNS=46 min preview --no-color | grep -q 'rebuilt'"
check "but never the number"              "COLUMNS=46 min preview --no-color | grep -q 'MB'"
check "and the disk line shortens too"    "! COLUMNS=38 min doctor --no-color | grep -q 'free of'"

# the prompt's list, and the plural that gave it "2 looses": nimo_plural takes
# one word, and two words unquoted is two arguments
list_at() { printf '/\n/quit\n' | COLUMNS="$1" NIMO_REPL_FORCE=1 NIMO_NO_CLEAR=1 HOME="$BOX" bash "$MIN" -q --no-color 2>&1; }

check "the / list keeps its words wide"   "list_at 80 | grep -q 'desktop, downloads'"
check "and drops them when narrow"        "! list_at 44 | grep -q 'desktop, downloads'"
check "but never the commands"            "list_at 44 | grep -q '/screenshots'"
check "loose screenshots, not looses"     "! list_at 80 | grep -q 'looses'"

# two functions with one name is a bug waiting for the day somebody calls the
# wrong one — this found exactly that, between lib/ui.sh and lib/scan.sh
check "no function is defined twice"      "[ -z \"\$(cat '$ROOT'/lib/*.sh | sed -n 's/^\(nimo_[a-z_]*\)() {.*/\1/p' | sort | uniq -d)\" ]"

# ---- putting a whole session back -----------------------------------------
#
# `min tidy` is six commands, so putting it back was six commands, in the
# right order, and knowing which. Newest first, because a later change can sit
# on top of an earlier one — undo the earlier one first and the later one is
# put straight back on top of it.

ALLBOX="$BOX/undo-all"
mkdir -p "$ALLBOX/Desktop" "$ALLBOX/Documents"
touch "$ALLBOX/Desktop/one.txt" "$ALLBOX/Desktop/two.txt" "$ALLBOX/Desktop/three.txt"
printf 'words in here\n' > "$ALLBOX/Documents/notes.txt"

allmin() { HOME="$ALLBOX" bash "$MIN" "$@" -q --no-color </dev/null 2>&1; }
allmin desktop -y >/dev/null 2>&1
allmin blank "$ALLBOX/Documents/notes.txt" -y >/dev/null 2>&1

check "two things happened"               "[ -d \"$ALLBOX/Desktop/Tidy\" ] && [ ! -s \"$ALLBOX/Documents/notes.txt\" ]"
check "--all --dry-run lists them"        "[ \$(allmin undo --all -n | grep -c 'emptied a file\|cleared your desktop') = 2 ]"
check "and a dry run puts nothing back"   "[ -d \"$ALLBOX/Desktop/Tidy\" ]"
check "--all needs a yes off a terminal"  "allmin undo --all | grep -q 'not a terminal'"

check "--all puts everything back"        "allmin undo --all -y | grep -q '2 things put back'"
check "the desktop is as it was"          "[ -f \"$ALLBOX/Desktop/one.txt\" ] && [ -f \"$ALLBOX/Desktop/three.txt\" ]"
check "and the file has its words again"  "grep -q 'words in here' \"$ALLBOX/Documents/notes.txt\""
check "and there is nothing left to undo" "allmin undo --list | grep -q 'not changed anything'"
check "the record of it is kept, not lost" "ls \"$ALLBOX/.nimo/undo/done\"/*.tsv >/dev/null 2>&1"
rm -rf "$ALLBOX"

# ---- min top steps into things --------------------------------------------
#
# "Where did my disk go" is a question about a tree, and a flat list of your
# home folder answers it once and then leaves you to guess. Picking a folder
# looks inside it; `..` comes back up; it stops at your home folder and goes
# no further, even though nothing in this command can change anything.

BIG="$BOX/bigtree"
mkdir -p "$BIG/Movies/holiday" "$BIG/Documents"
dd if=/dev/zero of="$BIG/Movies/holiday/clip.mov" bs=1024 count=3000 2>/dev/null
dd if=/dev/zero of="$BIG/Movies/trailer.mp4" bs=1024 count=900 2>/dev/null
dd if=/dev/zero of="$BIG/Documents/notes.pdf" bs=1024 count=40 2>/dev/null
dd if=/dev/zero of="$BIG/loose-file.iso" bs=1024 count=1500 2>/dev/null

# a literal newline in a variable: $(printf '\n') is stripped by the command
# substitution, and "enter" is the key every one of these is about
NL=$'\n'

top_keys() {
    printf '%s' "$1" | NIMO_PICK_FORCE=1 HOME="$BIG" bash "$MIN" top -q --no-color 2>&1
}

check "it lists the biggest first"        "[ \"\$(top_keys q | grep -A2 'biggest folders' | tail -1 | awk '{print \$1}')\" = 'Movies/' ]"
check "a loose file counts too"           "top_keys q | grep -q 'loose-file.iso'"
check "and folders are marked as folders" "top_keys q | grep -q 'Movies/'"

# enter on the first row steps in; the first row is the biggest, which is Movies
check "enter looks inside"                "top_keys \"\${NL}q\" | grep -q 'inside Movies'"
check "and what is in there is listed"    "top_keys \"\${NL}q\" | grep -q 'holiday/'"
# inside a folder the first row is `..`, so going deeper is enter, down, enter
check "two steps go two deep"             "top_keys \"\${NL}j\${NL}q\" | grep -q 'inside Movies/holiday'"
check "and the file at the bottom shows"  "top_keys \"\${NL}j\${NL}q\" | grep -q 'clip.mov'"

# the first row from inside a folder is `..`
check ".. is the first row, and comes up"  "[ \"\$(top_keys \"\${NL}\${NL}q\" | grep -c 'biggest folders')\" = 2 ]"
check "q says it changed nothing"         "top_keys q | grep -q 'only ever measures'"
check "and it never offers to delete"     "! top_keys q | grep -qi 'delete\\|remove\\|free up'"

# off a terminal it is the flat list it always was, and says where the rest is
check "off a tty it just prints"          "HOME=\"$BIG\" bash \"$MIN\" top -q --no-color </dev/null | grep -q 'Movies'"
check "and points at the way in"          "HOME=\"$BIG\" bash \"$MIN\" top -q --no-color </dev/null | grep -q 'step into these'"
rm -rf "$BIG"

# ---- machine readable, and readable by a machine -------------------------
#
# --json is the one output nimo makes that nobody reads with their eyes, which
# is exactly why it needs checking: a stray comma or an unquoted label is
# invisible to everybody until a script falls over on it. So a parser reads
# it, not a grep.

valid_json() {
    min "$@" --json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in ("nimo", "disk", "targets", "safe_bytes", "review_bytes"):
    assert k in d, k
assert isinstance(d["targets"], list) and d["targets"], "no targets"
for t in d["targets"]:
    for k in ("id", "label", "safety", "bytes", "items"):
        assert k in t, k
    assert isinstance(t["bytes"], int)
    assert isinstance(t["items"], int)
    assert t["safety"] in ("safe", "review"), t["safety"]
assert isinstance(d["disk"]["free_bytes"], int)
'
}

check "preview --json parses"             "valid_json preview"
check "clean --json parses too"           "valid_json clean -n"
check "the version in it is the version"  "min preview --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"nimo\"])' | grep -qx \"\$(tr -d ' \n' < '$ROOT/VERSION')\""
check "and it says nothing else at all"   "[ \"\$(min preview --json | head -1)\" = '{' ]"

# ---- the way in ---------------------------------------------------------

check "bare min prints help off a tty"    "min --no-color | grep -q 'Commands'"
# The arrow menu is built per platform too: on Linux there is no wallpaper to
# set and no dock to thin out, and offering them was offering an apology.
menu_here() { printf 'q' | NIMO_PICK_FORCE=1 HOME="$BOX" bash "$MIN" --menu --no-color 2>&1; }

check "the menu lists what runs here"     "menu_here | grep -q 'desktop' && menu_here | grep -q 'clean'"
check "and the downloads with them"       "menu_here | grep -q 'downloads'"
check "no wallpaper to set on linux"      "! menu_here | grep -q 'wallpaper'"
check "and no dock to thin out"           "! menu_here | grep -q 'dock'"
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

# The blink moves the cursor up six rows and back. It used to come back with
# `\033[u`, which is not the same escape on every terminal — on the ones that
# ignore it the cursor simply stayed six rows up, and nimo printed its prompt,
# its hint and its whole menu straight over its own face. Nothing text-based
# could see it: the bytes were all correct, the screen was not. So these run
# the stream through a terminal instead of a grep.
anim() {
    printf '/quit\n' | NIMO_ANIMATE_FORCE=1 NIMO_REPL_FORCE=1 NIMO_NO_CLEAR=1 \
        HOME="$BOX" bash "$MIN" --no-color 2>&1
}
still() {
    printf '/quit\n' | NIMO_REPL_FORCE=1 NIMO_NO_CLEAR=1 \
        HOME="$BOX" bash "$MIN" --no-animation --no-color 2>&1
}

check "the blink saves no cursor"         "! anim | cat -v | grep -q '\^\[\[[su]'"
check "what goes up comes back down"      "[ \"\$(anim | cat -v | grep -o '\^\[\[6A' | wc -l)\" = \"\$(anim | cat -v | grep -o '\^\[\[6B' | wc -l)\" ]"
check "blinking leaves the same screen"   "diff -q <(anim | python3 \"$ROOT/tools/screen.py\") <(still | python3 \"$ROOT/tools/screen.py\")"
check "and the prompt is below the face"  "[ \"\$(anim | python3 \"$ROOT/tools/screen.py\" | grep -n 'nimo . /quit' | head -1 | cut -d: -f1)\" -gt 10 ]"

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
check "--auto is the flag for /auto"      "printf '/quit\\n' | NIMO_REPL_FORCE=1 HOME=\"$BOX\" bash \"$MIN\" --auto -q --no-color 2>&1 | grep -q 'nimo auto'"
# The list you get for "/" is built, not written out: it counts what is
# actually lying about, and it only offers what this computer can do.
slash() { printf '/\n/quit\n' | NIMO_REPL_FORCE=1 NIMO_NO_CLEAR=1 HOME="$BOX" bash "$MIN" -q --no-color 2>&1; }

check "the list is grouped, not a wall"   "[ \$(slash | grep -c 'clear something\|make it yours\|get the disk back') = 3 ]"
# a home of its own, so whatever the rest of the suite has left lying around
# in $BOX cannot answer this question for it
EMPTY="$BOX/empty-home"
mkdir -p "$EMPTY/Desktop" "$EMPTY/Downloads"
slash_in() { printf '/\n/quit\n' | NIMO_REPL_FORCE=1 NIMO_NO_CLEAR=1 HOME="$1" bash "$MIN" -q --no-color 2>&1; }

check "it counts your desktop for you"    "touch \"$EMPTY/Desktop/a.txt\" \"$EMPTY/Desktop/b.txt\"; slash_in \"$EMPTY\" | grep -q '2 items on your desktop'"
check "and says so when it is clear"      "rm -f \"$EMPTY/Desktop/a.txt\" \"$EMPTY/Desktop/b.txt\"; slash_in \"$EMPTY\" | grep -q 'already clear'"
check "no zero-loose-screenshots line"    "! slash | grep -q '0 loose'"
check "the list offers /startup"           "slash | grep -q '/startup'"
check "and /next, for the wallpapers"     "slash | grep -q '/next'"
check "every group has rows under it"     "[ \$(slash | grep -c '^ *[▤▼▽▣◐◑◇■▸◍◆⧉▢↺○●] /') -ge 12 ]"

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

# It asked "Which one? (1-7):" and never said what 1 to 7 were. Off a terminal
# — a pipe, a script, ssh with no tty — every menu nimo has was an unanswerable
# question, and `min clear` is the menu people meet first.
menu_off_tty() { printf '\n' | HOME="$BOX" bash "$MIN" clear --no-color 2>&1; }

check "the plain menu lists its options"  "menu_off_tty | grep -qi 'desktop'"
check "and numbers them"                  "menu_off_tty | grep -q '^ *1  '"
check "as many lines as it offers"        "[ \"\$(menu_off_tty | sed -n 's/.*Which one? 1-\\([0-9]*\\).*/\\1/p')\" = \"\$(menu_off_tty | grep -c '^ *[0-9]  ')\" ]"
check "typing all ticks everything"       "[ \"\$(printf 'all\\n' | pick_plain multi)\" = '1 2 3 4' ]"

# ---- the undo history ---------------------------------------------------

mkdir -p "$BOX/Desktop"

# `grep -c .` prints 0 and exits 1 on an empty file, so the obvious
# $(grep -c . "$f" || echo 0) produced "0" and then a second "0" — a count
# with a newline in the middle of it. It went straight into the label, the
# label took two rows, and the numbers you were being asked to pick from no
# longer lined up with the things they named.
mkdir -p "$BOX/.nimo/undo" "$BOX/.nimo/backups"
: > "$BOX/.nimo/undo/desktop-20260101-000000.tsv"
: > "$BOX/.nimo/backups/setup-20260101-000001.tsv"

check "an empty log is not offered"       "! min undo --list --no-color | grep -q '0 files\|0 settings'"
check "and no label ever wraps a line"    "! min undo --list --no-color | grep -q '^ *[0-9]* *[0-9]* [a-z]*s$'"

printf 'a\tb\n' > "$BOX/.nimo/undo/desktop-20260101-000000.tsv"
check "a log with something in it is"     "min undo --list --no-color | grep -q 'cleared your desktop'"
check "and it says how many files"        "min undo --list --no-color | grep -q '1 file'"
rm -f "$BOX/.nimo/undo/desktop-20260101-000000.tsv" "$BOX/.nimo/backups/setup-20260101-000001.tsv"
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

# ---- the app people download -------------------------------------------
#
# None of this compiles Swift — there is no Mac here. It checks the thing
# that actually rots: the menu naming a command min no longer has, or the
# bundle being assembled without a library min sources.

APP="$ROOT/app"

check "the app has a source, a plist and a build" \
    "[ -f '$APP/Sources/main.swift' ] && [ -f '$APP/Info.plist' ] && [ -x '$APP/build.sh' ]"
check "the build script parses"           "bash -n '$APP/build.sh'"
check "there is one icon to change"       "[ -f '$ROOT/assets/app/icon-1024.png' ]"
check "and nothing the app no longer draws" \
    "! ls '$APP/Resources'/menubar* >/dev/null 2>&1"

check "the app is a normal app, not a menu bar one" \
    "! grep -q 'LSUIElement' '$APP/Info.plist'"
check "it puts an icon in the Dock"       "grep -q 'setActivationPolicy(.regular)' '$APP/Sources/main.swift'"
check "it opens a window when it starts"  "grep -q 'makeKeyAndOrderFront' '$APP/Sources/main.swift'"
check "it has a menu bar of its own"      "grep -q 'NSApp.mainMenu = buildMenu' '$APP/Sources/main.swift'"
check "you can quit it"                   "grep -q 'NSApplication.terminate' '$APP/Sources/main.swift'"
check "nimo's panel is read back into real controls" \
    "grep -q 'enum Report' '$APP/Sources/main.swift' && grep -q 'case heading' '$APP/Sources/main.swift'"
DOUBLE=$(awk '/^final class /{c=$3} /required init\?\(coder/{print c}' "$APP/Sources/main.swift" | sort | uniq -d)
# A Swift keyword used as a name is a compile error, and `let where = ...` is
# the one that reads like ordinary English. `guard let self` is not that.
KEYWORD=$(grep -nE "^ *(let|var) (where|case|default|in|is|as|for|if|else|func|class|struct|enum|return|switch|guard|try|throw|super|repeat|while|do|init|deinit|protocol|extension|import|operator|subscript|typealias|inout|nil|true|false) *=" "$APP/Sources/main.swift" | head -3)
check "nothing is named after a Swift keyword" "[ -z '$KEYWORD' ]"

# Slicing a class out and writing a new one back is how helpers go missing,
# and the compiler only says so a build later. Every method called through
# self, and every selector naming one of our own, has to exist here.
MISSING=$(awk '
    /func [a-zA-Z_]+\(/ { line = $0
        sub(/.*func /, "", line); sub(/\(.*/, "", line); have[line] = 1 }
    { s = $0
      while (match(s, /self\??\.[a-zA-Z_]+\(/)) {
        call = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        sub(/^self\??\./, "", call); sub(/\($/, "", call); want[call] = 1 }
      t = $0
      while (match(t, /#selector\(Main\.[a-zA-Z_]+/)) {
        call = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
        sub(/.*Main\./, "", call); want[call] = 1 } }
    END { for (n in want) if (!(n in have) && n != "init") print n }' "$APP/Sources/main.swift")
check "every method the file calls, the file defines" "[ -z '$MISSING' ]"
check "no class overrides init(coder:) twice" "[ -z '$DOUBLE' ]"
# Slicing a block out and writing a new one back can leave both. A name that
# appears twice is a compile error, and the shape of that mistake.
TWICE=$(grep -o '^final class [A-Za-z]*' "$APP/Sources/main.swift" | sort | uniq -d)
check "no class is declared twice"          "[ -z '$TWICE' ]"
# A property declared with ! and never assigned is nil the moment something
# reads it — which, in a window, is at launch. That is the shape of the bug
# that shipped an app which would not open, so the suite reads for it.
UNSET=$(awk '
    /private var [A-Za-z_]+: [A-Za-z<>\[\], ]+!/ {
        name = $3; sub(":", "", name); wanted[name] = 1
    }
    { for (n in wanted) if ($0 ~ ("^ *" n " = ")) delete wanted[n] }
    END { for (n in wanted) print n }' "$APP/Sources/main.swift")
check "nothing declared with ! is left unassigned" "[ -z '$UNSET' ]"
check "nimo draws its own buttons, centred"  \
    "grep -q 'final class Chip' '$APP/Sources/main.swift' && ! grep -q 'bezelStyle = .rounded' '$APP/Sources/main.swift'"
check "and every page is on the keyboard"   \
    "grep -q 'func goByNumber' '$APP/Sources/main.swift' && grep -q 'keyEquivalent: \\\",\\\"' '$APP/Sources/main.swift'"
check "the menu is built after the window it points at" \
    "grep -A2 'func applicationDidFinishLaunching' '$APP/Sources/main.swift' | grep -q 'main = Main()'"
# A terminal in the window would be an NSTextView built and filled. The type
# also turns up in NSTextFieldDelegate's signature, which is not one.
check "there is no terminal left in the window" \
    "! grep -qE 'NSTextView\\(|documentView = .*NSTextView' '$APP/Sources/main.swift'"
check "what nimo said is laid out as text"  "grep -q 'final class Said' '$APP/Sources/main.swift'"
# The window has no colour in it. Every dashboard reaches for a brand hue and
# puts it on the button, the selected row, the first bar of the chart and the
# icon beside a job — four coloured things, which is four things shouting.
# What matters is brighter, what does not is dimmer, and the only colour in
# the window is whatever is behind the glass.
check "the window is grey all the way down" \
    "! grep -qE 'NSColor\\.(systemBlue|systemTeal|systemGreen|systemOrange|systemPurple|systemPink|systemYellow)' '$APP/Sources/main.swift'"
check "and every colour it has is told twice, light and dark" \
    "[ \$(grep -c 'static let [a-z]* *= duo(0x' '$APP/Sources/main.swift') -ge 12 ]"
check "and it is spent in one place at a time" \
    "[ \$(grep -c 'Paint.accent' '$APP/Sources/main.swift') -le 12 ]"
check "the window follows the system, light or dark" \
    "grep -q 'bestMatch(from: \[.aqua, .darkAqua\])' '$APP/Sources/main.swift' && ! grep -q 'window.appearance' '$APP/Sources/main.swift'"
# Glass, with a veil of Kliner's own slate over it. Straight glass took its
# colour from the wallpaper — on a warm photograph the whole app went brown —
# and a flat opaque window threw the depth away with it.
check "the window is glass"                 "grep -q 'NSVisualEffectView()' '$APP/Sources/main.swift'"
check "and it lets the desktop through"     "grep -q 'window.isOpaque = false' '$APP/Sources/main.swift'"
check "but the wallpaper's colour does not reach the page" \
    "grep -q 'static let veil = duo' '$APP/Sources/main.swift' \
     && grep -q 'Surface(Paint.veil)' '$APP/Sources/main.swift'"
check "the window opens on a look, not a job" \
    "grep -q 'static let home = Action' '$APP/Sources/main.swift' && grep -q 'func drawHome' '$APP/Sources/main.swift'"
check "home is doctor's own reading, not a second measurement" \
    "grep -q 'home = Action(title: \\\"Home\\\"' '$APP/Sources/main.swift'"
check "home offers access when something is shut" \
    "grep -q 'askFromHome' '$APP/Sources/main.swift'"
check "there is a settings page"            "grep -q 'func drawSettings' '$APP/Sources/main.swift'"
check "every page can undo itself"          "[ \$(grep -c 'Put this back' '$APP/Sources/main.swift') -ge 3 ]"
check "you can step into a folder"          "grep -q 'func walkInto' '$APP/Sources/main.swift' && grep -q 'walks: true' '$APP/Sources/main.swift'"
check "and step back out of it"             "grep -q 'func walkUp' '$APP/Sources/main.swift'"
check "a page can open its folder in Finder" "grep -q 'inFileViewerRootedAtPath' '$APP/Sources/main.swift'"
# Five places, not nine rows under four headings. What is inside a place is
# on the place's own page, as tabs across the top of it.
check "the list down the side is five places" \
    "grep -q 'static let places: \\[Place\\]' '$APP/Sources/main.swift' && [ \$(grep -c '^        Place(title:' '$APP/Sources/main.swift') = 5 ]"
# A row of tabs said the same thing twice, once in the trail and once under
# it. The name of the thing you are looking at is where you change it.
check "and a place holding two things offers both" \
    "grep -q 'func offerSiblings' '$APP/Sources/main.swift' && grep -q 'final class Trail' '$APP/Sources/main.swift' && ! grep -q 'final class Tab' '$APP/Sources/main.swift'"
check "the row is lit for the page inside it" \
    "grep -q 'Action.place(of: row.index)?.holds.contains(index)' '$APP/Sources/main.swift'"
check "help sits under settings, with the keys" \
    "grep -q 'func drawHelp' '$APP/Sources/main.swift' && grep -q 'static let help = Action' '$APP/Sources/main.swift'"
check "it can ask macOS for what it needs"  "grep -q 'func askForFolders' '$APP/Sources/main.swift' && grep -q 'func askNext' '$APP/Sources/main.swift'"
check "and it never claims to grant itself access" \
    "grep -q 'enum Access' '$APP/Sources/main.swift' && grep -q 'Privacy_AllFiles' '$APP/Sources/main.swift'"
check "settings are the same file nimo reads" \
    "grep -q '.nimo\\\", isDirectory' '$APP/Sources/main.swift' && grep -q 'enum Config' '$APP/Sources/main.swift'"
# A clip view that is not flipped puts a short page at the bottom of the
# window, which is what left a hole above every one of them.
check "the page starts at the top of the window" \
    "grep -q 'final class TopClip' '$APP/Sources/main.swift' && grep -q 'scroll.contentView = TopClip' '$APP/Sources/main.swift'"
check "waiting is the face, with nothing written on it" \
    "grep -q 'final class Thinking' '$APP/Sources/main.swift' && ! grep -q 'one moment' '$APP/Sources/main.swift'"
check "and something turns while it waits"  "grep -q 'CAShapeLayer' '$APP/Sources/main.swift'"
check "both eyes shut when it blinks"       \
    "python3 '$ROOT/tools/blinkcheck.py' '$APP/Resources/wordmark-blink@3x.png'"
check "and the open frame is not two lids"  \
    "! python3 '$ROOT/tools/blinkcheck.py' '$APP/Resources/wordmark@3x.png'"
check "the face has two eyes, not one"      \
    "python3 '$ROOT/tools/blinkcheck.py' --holes '$APP/Resources/mascot-blink@3x.png'"
check "and shuts them, rather than thickening them" \
    "python3 '$ROOT/tools/blinkcheck.py' --shut '$APP/Resources/mascot-blink@3x.png' '$APP/Resources/mascot@3x.png'"
check "which is a real comparison, not a coincidence" \
    "! python3 '$ROOT/tools/blinkcheck.py' --shut '$APP/Resources/mascot@3x.png' '$APP/Resources/mascot-blink@3x.png'"
check "the face is drawn in the page's own ink" \
    "grep -q 'picture?.isTemplate = true' '$APP/Sources/main.swift'"
check "a blink is a movement, not a flicker" \
    "[ -f '$APP/Resources/wordmark-half@3x.png' ] && [ -f '$APP/Resources/mascot-half@3x.png' ] && grep -q 'Three frames to shut an eye, not two' '$APP/Sources/main.swift'"
check "the halfway eye is between open and shut" \
    "python3 '$ROOT/tools/blinkcheck.py' --shut '$APP/Resources/mascot-half@3x.png' '$APP/Resources/mascot@3x.png' >/dev/null; [ \$? = 1 ] && python3 '$ROOT/tools/blinkcheck.py' --shut '$APP/Resources/mascot-blink@3x.png' '$APP/Resources/mascot-half@3x.png'"
check "the ring goes round the face, not round a circle" \
    "grep -q 'static let outline' '$APP/Sources/main.swift' && grep -q 'travelling' '$APP/Sources/main.swift'"
check "an answer only lands on the page that asked" \
    "grep -q 'let asked = chosen' '$APP/Sources/main.swift' && grep -q 'guard self.chosen == asked' '$APP/Sources/main.swift'"
check "the face waits, not a spinner"        \
    "grep -q 'final class Thinking' '$APP/Sources/main.swift' && ! grep -q 'NSProgressIndicator' '$APP/Sources/main.swift'"
check "the eyes in the wordmark blink"      \
    "grep -q 'final class Wordmark' '$APP/Sources/main.swift' && [ -f '$APP/Resources/wordmark-blink.png' ]"
check "the list folds down to its pictures"  \
    "grep -q 'func foldSide' '$APP/Sources/main.swift' && grep -q 'func narrow' '$APP/Sources/main.swift'"
check "and a folded row keeps its name"     "grep -q 'toolTip = yes ? name.stringValue' '$APP/Sources/main.swift'"
# Home is cards now: the number, the bar it came out of, then the table
# behind the bar. Each of the three has to be there, in that order, or the
# page is a figure with no working shown.
check "home is laid out as cards"            \
    "grep -q 'final class Card' '$APP/Sources/main.swift' && grep -q 'let card = Card(\"What is on your disk\")' '$APP/Sources/main.swift'"
# The figures across the top, then the bar they came out of, then the table
# behind the bar. Out of that order it is three unrelated pictures.
# Home ran out two thirds of the way down the window and what was under it
# was nothing. The last thing on it is the one question anybody has before
# they press any of the buttons above it.
# Home reads itself every half minute. Open another page while that reading
# is in flight and `run` returned at its own guard without a word: you got the
# new page's title, the new page's button, and the last page's body under
# both. It puts the face up and asks again the moment the machine is free.
check "a page opened while something is running does not show the last one" \
    "grep -q 'wanted = chosen' '$APP/Sources/main.swift' \
     && grep -q 'private func serveWanted() -> Bool' '$APP/Sources/main.swift' \
     && [ \$(grep -c 'if self.serveWanted() { return }' '$APP/Sources/main.swift') = 2 ]"
check "and it waits with a face, not with the wrong page" \
    "awk '/private func run\\(_ item: Action/,/^        wanted = nil/' '$APP/Sources/main.swift' | grep -q 'waiting()'"

check "home closes on what it promises" \
    "grep -q 'Card(\"Nothing here is deleted\")' '$APP/Sources/main.swift' \
     && grep -q 'safe.foot(\"Put something back\")' '$APP/Sources/main.swift'"
# Nothing pulled a legend entry's right edge in, so three of them spread
# themselves across the whole card instead of standing next to each other.
check "a legend entry is as wide as its own words" \
    "grep -q 'hug.priority = .defaultLow' '$APP/Sources/main.swift' \
     && grep -q 'hugToo.priority = .defaultLow' '$APP/Sources/main.swift'"

check "the figures sit above the bar" \
    "awk '/across.addArrangedSubview\\(Metric\\(\"Disk\"/{m=NR} /card.add\\(Split\\(bands\\)/{s=NR} END{exit !(m && s && m<s)}' '$APP/Sources/main.swift'"
# The bar and the table under it were the same three numbers twice. The bar
# carries its own reading now, and there is no table.
check "and the bar carries its own reading" \
    "! sed -n '/what is taking the room/,/^    }/p' '$APP/Sources/main.swift' | grep -q 'Ledger(' && grep -q 'Key(part.name, part.colour, part.note)' '$APP/Sources/main.swift'"
check "a figure with a ceiling gets a meter" \
    "grep -q 'final class Meter' '$APP/Sources/main.swift' && grep -q 'of: size(total)' '$APP/Sources/main.swift'"
# One colour at falling strengths, not a palette. A breakdown in five colours
# is a chart to be decoded.
check "the breakdown is drawn in one colour" \
    "grep -q 'static func band(' '$APP/Sources/main.swift' && ! grep -qE '\\.system(Blue|Purple|Pink|Orange|Teal|Indigo|Green)' '$APP/Sources/main.swift'"
# Proportional widths and a gap between the pieces cannot both be constraints
# without one of them being broken, so the bar lays itself out.
check "the bar is cut in proportion, not by eye" \
    "grep -q 'room \\* CGFloat(parts\\[i\\].share / whole)' '$APP/Sources/main.swift'"
check "what is big is a breakdown too"       \
    "grep -q 'func drawBreakdown' '$APP/Sources/main.swift' && grep -q 'Everything else' '$APP/Sources/main.swift'"
check "and its folders still open"           \
    "grep -q 'walkable: one.folder' '$APP/Sources/main.swift'"
# A page about a folder lists things in that folder, and a thing in a folder
# is something you can open.
check "a row opens the thing it names"       \
    "grep -q 'func openThing' '$APP/Sources/main.swift' && grep -q 'self?.openThing(label)' '$APP/Sources/main.swift'"
check "and it looks in Tidy when it has been tidied" \
    "grep -q 'appendingPathComponent(\"Tidy\")' '$APP/Sources/main.swift'"
# A page saying how much room is left on a disk is out of date the moment it
# is drawn.
check "home takes its reading again"         \
    "grep -q 'func tick()' '$APP/Sources/main.swift' && grep -q 'quietly: true' '$APP/Sources/main.swift'"
check "but never while something is running" \
    "grep -q 'guard self.chosen == 0, !self.busy, !self.welcoming' '$APP/Sources/main.swift'"
check "and the breakdown has the picture as well as the table" \
    "grep -q 'final class Bars' '$APP/Sources/main.swift' && grep -q 'card.add(Bars(named.map' '$APP/Sources/main.swift'"
check "sizes are read back into numbers"    "grep -q 'func bytes' '$APP/Sources/main.swift'"
check "no paragraph under every title"      "! grep -q 'blurbLabel' '$APP/Sources/main.swift'"
# The work is one card, inset from three edges of the window and round at the
# corners. The list is not on it: the list is on the glass.
check "the work sits on one card, inset from the window" \
    "grep -q 'Surface(Paint.card, round: 12, edged: true)' '$APP/Sources/main.swift' \
     && grep -q 'pane.trailingAnchor.constraint(equalTo: content.trailingAnchor,' '$APP/Sources/main.swift'"
check "and Kliner sits in the corner of the card" \
    "grep -q 'sitting.trailingAnchor.constraint(equalTo: pane.trailingAnchor,' '$APP/Sources/main.swift' \
     && grep -q 'sitting.bottomAnchor.constraint(equalTo: pane.bottomAnchor,' '$APP/Sources/main.swift'"
check "the window is two surfaces, not one" \
    "[ \$(grep -c 'Surface(Paint' '$APP/Sources/main.swift') = 2 ]"
check "back and forward remember where you were" \
    "grep -q 'func goBack' '$APP/Sources/main.swift' && grep -q 'behind.append' '$APP/Sources/main.swift'"
check "the chrome sits past the three lights" \
    "grep -q 'chromeLeading' '$APP/Sources/main.swift'"
check "a quiet button is words until you point at it" \
    "grep -q 'hovering && live ? Paint.picked : NSColor.clear' '$APP/Sources/main.swift'"
check "a busy button dims, it does not go grey" \
    "grep -q 'if !live { strength = 0.4 }' '$APP/Sources/main.swift'"
check "screenshots is not its own page any more" \
    "! grep -q 'Action(title: \\\"Screenshots\\\"' '$APP/Sources/main.swift'"
check "a row of files can be opened"        "grep -q 'func openKind' '$APP/Sources/main.swift'"
check "the folded rail shows the face"      "grep -q 'func fold' '$APP/Sources/main.swift' && [ -f '$APP/Resources/mascot.png' ]"
check "the wordmark blinks when you point at it" \
    "grep -q 'override func mouseEntered' '$APP/Sources/main.swift' && grep -q 'Look at it and it looks back' '$APP/Sources/main.swift'"
# Ten point sizes on nine pages is what "nothing lines up" looks like from the
# outside. There is one type scale and one spacing scale, and nothing outside
# them names a number.
check "one type scale, and nothing outside it" \
    "grep -q 'enum Words {' '$APP/Sources/main.swift' && [ \$(grep -c 'ofSize:' '$APP/Sources/main.swift') = \$(sed -n '/^enum Words {/,/^}/p' '$APP/Sources/main.swift' | grep -c 'ofSize:') ]"
check "one spacing scale as well"            \
    "grep -q 'enum Step {' '$APP/Sources/main.swift' && grep -q 'static let air:   CGFloat' '$APP/Sources/main.swift'"
check "the page arrives a line at a time"   \
    "grep -q 'CAAnimationGroup' '$APP/Sources/main.swift' && grep -q 'arriving' '$APP/Sources/main.swift'"
check "and a colour is eased, never snapped" \
    "grep -q 'func ease' '$APP/Sources/main.swift' && ! grep -q 'layer?.backgroundColor = background.cgColor' '$APP/Sources/main.swift'"
check "its version is filled in at build" "grep -q '__VERSION__' '$APP/Info.plist'"
check "build.sh fills it in"              "grep -q 's/__VERSION__/' '$APP/build.sh'"
check "the plist names the executable"    "grep -q '<string>Kliner</string>' '$APP/Info.plist'"
check "the app is called Kliner"          "grep -q 'app.kliner.mac' '$APP/Info.plist' && grep -q 'Kliner.app' '$APP/build.sh'"
check "and called it nowhere else"        \
    "! grep -q 'Nimo' '$APP/build.sh' && ! grep -q 'Nimo' '$APP/install-app.sh' && ! grep -q 'Nimo' '$APP/Info.plist'"
check "and points at its own site"        "grep -q 'kliner.app' '$APP/Sources/main.swift'"

# Every command the menu offers has to be a command min answers to. This is
# the check that catches a renamed command months from now.
APP_CMDS=$(sed -n 's/.*arguments: \[\"\([a-z]*\)\".*/\1/p' "$APP/Sources/main.swift" | sort -u)
check "the menu names commands"           "[ -n '$APP_CMDS' ]"
# the one line in min that lists every word it will answer to
KNOWN=$(grep -m1 -o '^ *[a-z]*|clean|preview|[a-z|]*)' "$MIN" | tr -d ' )')
check "min's own list of commands is readable" "[ -n '$KNOWN' ]"
UNKNOWN=""
for c in $APP_CMDS; do
    case "|$KNOWN|" in
        *"|$c|"*) ;;
        *) UNKNOWN="$UNKNOWN $c" ;;
    esac
done
check "every command in the menu exists"  "[ -z '$UNKNOWN' ]"

# --yes is the app's way of saying somebody clicked. It must never be a
# constant.
check "--yes is not hard-wired into the menu" \
    "! grep -qE 'arguments: \[\"[a-z]+\", \"--yes\"' '$APP/Sources/main.swift'"
check "--yes is added only after a dialog" \
    "grep -q 'item.asks == nil ? item.arguments : item.arguments' '$APP/Sources/main.swift'"
check "the app never gets a terminal to answer with" \
    "grep -q 'standardInput = FileHandle.nullDevice' '$APP/Sources/main.swift'"
check "the app reads the pipe before it waits" \
    "grep -B2 'waitUntilExit' '$APP/Sources/main.swift' | grep -q 'readDataToEndOfFile'"

# The bundle has to carry every library min sources, or the app is a menu
# over nothing.
check "the build copies min itself"       "grep -q 'cp min VERSION' '$APP/build.sh'"
check "the build copies the libraries"    "grep -q 'cp -R lib' '$APP/build.sh'"
check "the build signs the app"           "grep -q 'codesign --force' '$APP/build.sh'"
# An ad-hoc signature changes with every byte of the app, and macOS forgets
# what you allowed the moment it does. A signing identity of its own is what
# stops the endless asking.
check "and signs it as the same app each time" \
    "grep -q 'Kliner Local' '$APP/build.sh' && grep -q 'find-identity' '$APP/build.sh'"
check "with a way back if that fails"     \
    "grep -q 'falling back to an ad-hoc signature' '$APP/build.sh'"
check "the build makes both architectures" "grep -q 'for arch in arm64 x86_64' '$APP/build.sh'"
check "the build never ships the tests"   "! grep -q 'cp -R test' '$APP/build.sh'"
check "there is one command that installs it" "[ -x '$APP/install-app.sh' ]"
check "the installer parses"              "bash -n '$APP/install-app.sh'"
check "the installer never calls sudo"    "! grep -qE '^[^#]*\\bsudo\\b' '$APP/install-app.sh'"
check "the installer falls back to ~/Applications" \
    "grep -q 'HOME/Applications' '$APP/install-app.sh'"
check "opening at login is asked for properly" \
    "grep -q 'SMAppService' '$APP/Sources/main.swift'"
check "and only where macOS has a way to"  "grep -q '#available(macOS 13.0' '$APP/Sources/main.swift'"
check "a page fills itself in without changing anything" \
    "grep -q 'run(item, preview: true)' '$APP/Sources/main.swift' && grep -q 'item.looksOnly' '$APP/Sources/main.swift'"
check "arriving on Wallpaper does not change it" \
    "grep -q 'looksOnly: false' '$APP/Sources/main.swift'"
check "the eye looks about when it opens"   "grep -q '\"-left\" : \"-right\"' '$APP/Sources/main.swift'"
# Shut, round, a pair of dashes, shut again, and back to the quotes. A face
# with one expression is a picture; a face with three is somebody.
# The setup is the only thing on the window until it is finished, it arrives
# from the side it came from, and the last button asks to be pressed.
check "the setup shows nothing but itself"   \
    "grep -q 'func bare(' '$APP/Sources/main.swift' && grep -q 'bare(true)' '$APP/Sources/main.swift' && grep -q 'bare(false)' '$APP/Sources/main.swift'"
# A page of results settles down the page, a row at a time. A page explaining
# something wants the other axis: the face, then the headline, then each line
# coming in from the side it was going, further apart, so it reads as somebody
# laying things out rather than a page appearing.
check "and its pages are laid out, not just shown" \
    "grep -q 'func teach(' '$APP/Sources/main.swift' && grep -q 'let side: CGFloat = firstLook ? 0 : (step >= last ? 1 : -1)' '$APP/Sources/main.swift'"
# The face was already here. Animating it along with the words is what made
# every page of the setup read as a new screen rather than the next thing.
check "and the face does not arrive with the words" \
    "grep -q 'if view === marker {' '$APP/Sources/main.swift' && grep -q 'guard first else { continue }' '$APP/Sources/main.swift'"
# A row of dots that redraws does not tell you which way you just went.
# Four dots at the bottom were a decoration you had to count. All three flows
# this follows put the step at the top of the working pane and write it out.
check "and how far in you are is written, not drawn" \
    "grep -q 'final class Marker' '$APP/Sources/main.swift' && grep -q 'count.say(step)' '$APP/Sources/main.swift' && ! grep -q 'final class Dots' '$APP/Sources/main.swift'"
# The rail stays through the whole setup: brand and a line about it down one
# side, the step on the other. Folding it away made a different app for four
# pages and then yours.
check "and the rail is not folded away for it" \
    "grep -q 'railLine?.isHidden = false' '$APP/Sources/main.swift' && grep -q 'aside?.isHidden = !yes' '$APP/Sources/main.swift'"
# Back in the bottom-left of the pane, the one thing to press in the
# bottom-right, rather than both floating in the middle of the page.
check "and the way through sits in the corners" \
    "grep -q 'ahead.bottomAnchor.constraint(equalTo: pane.bottomAnchor' '$APP/Sources/main.swift' \
     && grep -q 'ahead.leadingAnchor.constraint(equalTo: pane.leadingAnchor' '$APP/Sources/main.swift'"
# Beckoning steps aside for leaning, so coming back off the last page has to
# put him down again or he keeps the round eyes on a page asking nothing.
check "and he stops asking when you walk back off it" \
    "grep -q 'func relax()' '$APP/Sources/main.swift' && grep -q 'face.relax()' '$APP/Sources/main.swift'"
# Going back is going left, so the head is thrown to the right and springs home.
check "going back throws the head the other way" \
    "sed -n '/^final class Floating/,/^}/p' '$APP/Sources/main.swift' | grep -q 'func lean(_ way: CGFloat)' && grep -q 'let side = -way \* 30' '$APP/Sources/main.swift' && grep -q 'face.lean(side)' '$APP/Sources/main.swift'"
# Two animations on one key fight rather than add, and drift already turns him.
check "and it squashes rather than turning"  \
    "sed -n '/func lean(_ way/,/^    }/p' '$APP/Sources/main.swift' | grep -q 'transform.scale.x' && ! sed -n '/func lean(_ way/,/^    }/p' '$APP/Sources/main.swift' | grep -q 'rotation.z'"
check "and he comes up out of nothing the first time" \
    "grep -q 'func arrive()' '$APP/Sources/main.swift' && grep -q 'face.arrive()' '$APP/Sources/main.swift'"
# init runs before the window is ordered front, so an opening drawn there
# plays to an empty screen and you are shown its last frame.
check "and the opening waits for the window to be on screen" \
    "grep -q 'func open()' '$APP/Sources/main.swift' && grep -q 'main.open()' '$APP/Sources/main.swift' && ! sed -n '/^        build()/,/^    }/p' '$APP/Sources/main.swift' | grep -q 'drawWelcome()'"
check "and the window fades up rather than being there" \
    "grep -q 'window.alphaValue = 0' '$APP/Sources/main.swift' && grep -q 'window.animator().alphaValue = 1' '$APP/Sources/main.swift'"
# The face is what asks, not the button. On the pages before it, the thing to
# learn is that two fingers turn the page, so the page says so, once.
check "and the face asks for the last press" \
    "grep -q 'func beckon()' '$APP/Sources/main.swift' && grep -q 'face.beckon()' '$APP/Sources/main.swift'"
check "and the pages before it teach the swipe" \
    "grep -q 'final class Nudge' '$APP/Sources/main.swift' && grep -q 'line(Nudge())' '$APP/Sources/main.swift'"
check "and it has more than one face to wear" \
    "grep -q '(\"-round\", 0.42)' '$APP/Sources/main.swift' && [ -f '$APP/Resources/mascot-round@3x.png' ] && [ -f '$APP/Resources/wordmark-dash@3x.png' ]"
check "the first time, it introduces itself" \
    "grep -q 'func drawWelcome' '$APP/Sources/main.swift' && grep -q 'welcomed' '$APP/Sources/main.swift'"
check "the welcome is four pages, not one"  \
    "grep -q 'Marker(of: 4)' '$APP/Sources/main.swift' && grep -q 'case 3:' '$APP/Sources/main.swift'"
# Eight rows of text saying what each page does is a wall to read in somebody's
# first minute. Five marks that land one after another is the same answer.
check "and he walks the places rather than listing them" \
    "grep -q 'final class Walk' '$APP/Sources/main.swift' && grep -q 'Walk(Action.places)' '$APP/Sources/main.swift'"
# The setup asks and sets the app up out of the answers, rather than being
# four pages about what the app is. All three of the flows this follows are
# forms.
check "the setup asks rather than explains"  \
    "grep -q 'final class Ask' '$APP/Sources/main.swift' && grep -q 'what should I call you' '$APP/Sources/main.swift' && grep -q 'What should I start with' '$APP/Sources/main.swift'"
check "and what it is told is written down"  \
    "grep -q 'Config.set(\"name\", callMe)' '$APP/Sources/main.swift' && grep -q 'Config.set(\"start\", startWith)' '$APP/Sources/main.swift' && grep -q 'Config.set(\"tidy\", folder)' '$APP/Sources/main.swift'"
# ~/.nimo/config is the CLI's own file, so an answer changes what min does too.
check "into the same file the CLI reads"     \
    "grep -q 'tidy)  case' '$ROOT/lib/core.sh' && grep -q 'NIMO_TIDY_DIR_NAME' '$ROOT/lib/desktop.sh'"
# A folder to sort into is a name, not a route, in both halves of Kliner.
check "and a folder name is refused the same way in both" \
    "grep -q 'folder.contains(\"/\")' '$APP/Sources/main.swift'"
# Landing on Home after answering "what should I start with" is the app not
# having listened.
# A setup that asks you something and then never uses it is a form for its
# own sake.
check "and the name it asked for is used"    \
    "grep -q 'Config.value(\"name\")' '$APP/Sources/main.swift' && grep -q 'Good morning' '$APP/Sources/main.swift'"
check "and it opens where you said to start" \
    "grep -q 'func openStart()' '$APP/Sources/main.swift' && grep -q 'show(Main.page(for: wanted))' '$APP/Sources/main.swift'"
# Walking back to a question showed the default again rather than the answer.
check "and an answer survives walking back to it" \
    "grep -q 'private func harvest()' '$APP/Sources/main.swift' && grep -q 'drawWelcome() {\n        harvest()' '$APP/Sources/main.swift' || grep -q 'harvest()' '$APP/Sources/main.swift'"
# Somebody walking along a row and stopping at each thing is somebody showing
# you round. A row that simply appears is a page being shown to you.
check "and each mark lights as he reaches it" \
    "grep -q 'private func light(_ i: Int)' '$APP/Sources/main.swift' && grep -q 'self?.light(i)' '$APP/Sources/main.swift'"
check "and he bobs rather than hovering across" \
    "sed -n '/^final class Walk/,/^}/p' '$APP/Sources/main.swift' | grep -q 'forKey: \"bobbing\"' && sed -n '/^final class Walk/,/^}/p' '$APP/Sources/main.swift' | grep -q 'mascot-right'"
# A layer animation with only a toValue begins at the model value, which never
# moves, so each new leg would snap back to the beginning first.
check "and every leg says where it starts" \
    "! sed -n '/^final class Undoing/,/^}/p' '$APP/Sources/main.swift' | grep -q 'across.toValue = x$' || grep -q 'across.fromValue = from' '$APP/Sources/main.swift'"
# The one promise the whole app rests on, shown rather than said four times.
check "and it shows what putting it back looks like" \
    "grep -q 'final class Undoing' '$APP/Sources/main.swift' && grep -q 'undoing?.play(after:' '$APP/Sources/main.swift'"
# A splash before anything has happened is a thing to sit through. The face
# plays the setup out instead, once, over the app arriving underneath it.
check "and the face plays it out at the end" \
    "grep -q 'func curtain()' '$APP/Sources/main.swift' && grep -A3 'bare(false)' '$APP/Sources/main.swift' | grep -q 'curtain()' && ! grep -q 'labelWithString: \"Welcome\"' '$APP/Sources/main.swift'"
# One page shape, whichever page you are on: anything that came back as a
# list of things with a size each is drawn as a breakdown.
check "every page with numbers is drawn the same way" \
    "grep -q 'if isPage, sized(pieces) > 1 {' '$APP/Sources/main.swift' && grep -q 'func sized(' '$APP/Sources/main.swift'"
# Desktop and Downloads come back as kinds with a count each, which is as much
# a breakdown as a list of folder sizes is, and it gets drawn like one.
check "counts count as well as sizes"        \
    "grep -q 'func weigh(' '$APP/Sources/main.swift' && grep -q 'func inBytes(' '$APP/Sources/main.swift'"
check "and a count is not written as a size" \
    "grep -q 'asBytes ? size(much) : String(Int(much.rounded()))' '$APP/Sources/main.swift'"
# A folder is something to look inside, not something to hand to the Finder.
check "a folder on a page can be looked into" \
    "grep -q 'walked = \\[folder, name\\]' '$APP/Sources/main.swift' && grep -q 'offer(\"Look inside\")' '$APP/Sources/main.swift'"
check "and stepping back out returns to the page" \
    "grep -q 'if walked.isEmpty, isPage, Action.all\\[chosen\\].reveal != nil {' '$APP/Sources/main.swift'"
# The hint points at the page it is taking you to.
check "the swipe hint points forward"        \
    "grep -q 'systemSymbolName: \"chevron.right\"' '$APP/Sources/main.swift' && grep -q 'go.values = \\[0, 7, 0, 0, 0\\]' '$APP/Sources/main.swift'"
check "and it asks for access on the last one, not the first" \
    "awk '/switch step/{a=NR} /func askNext/{b=NR} END{exit !(a && b && a < b)}' '$APP/Sources/main.swift'"
# macOS does not come back until somebody has answered, so the row has to say
# it is asking before the ask, on a later turn of the runloop.
check "and it asks for them one at a time"   \
    "grep -q 'row.say(\"asking macOS now' '$APP/Sources/main.swift' && grep -q 'self?.askNext(i + 1)' '$APP/Sources/main.swift'"
check "and waits for each answer before the next" \
    "grep -q 'private static let gates' '$APP/Sources/main.swift' && grep -q 'Word.ask { yes in settled(yes) }' '$APP/Sources/main.swift'"
# Nothing to press while macOS is asking; the way on appears when the last of
# them has an answer.
check "and the way on waits for the last of them" \
    "grep -q '} else if asked {' '$APP/Sources/main.swift'"
check "you can walk back through it"        "grep -q 'self.step -= 1' '$APP/Sources/main.swift'"
check "or skip the asking"                  "grep -q 'Skip for now' '$APP/Sources/main.swift'"
check "and only the first time"             "grep -q 'Config.set(\\\"welcomed\\\"' '$APP/Sources/main.swift'"
check "the face drifts while it says hello" "grep -q 'final class Floating' '$APP/Sources/main.swift'"
# The setup is the app introducing itself, so the face is in it on every page,
# not only the first, and it leans over whatever has just been written.
check "the face is on every page of the setup" \
    "grep -q 'let face = mascot ?? Floating(size: 56)' '$APP/Sources/main.swift' && grep -q 'face.nod()' '$APP/Sources/main.swift'"
# It stands in the rail rather than on the page, so the page is the step and
# nothing else, the way all three of these flows are built.
check "and it stands in the rail, not on the page" \
    "grep -q 'aside.insertArrangedSubview(face, at: 0)' '$APP/Sources/main.swift'"
check "and nothing is drawn behind it"       \
    "! sed -n '/^final class Floating/,/^}/p' '$APP/Sources/main.swift' | grep -q 'private let disc'"
check "it moves on two clocks that never line up" \
    "grep -q 'forKey: \"drifting\"' '$APP/Sources/main.swift' && grep -q 'forKey: \"tilting\"' '$APP/Sources/main.swift' && grep -q 'forKey: \"swelling\"' '$APP/Sources/main.swift'"
# A Mac says "the one before" with two fingers. The setup is four pages and
# the app is a list of them, so both are somewhere to go.
check "a sideways push turns the page"       \
    "grep -q 'final class Pages' '$APP/Sources/main.swift' && grep -q 'func swipedBack' '$APP/Sources/main.swift'"
check "and a mouse wheel that goes sideways counts too" \
    "grep -q 'event.phase != \\[\\]' '$APP/Sources/main.swift'"
# A setup that has grown a page is a setup nobody has read. Stamping which one
# was read, rather than that one was, is what shows it again.
check "a setup nobody has seen is shown once more" \
    "grep -q 'static let setup = ' '$APP/Sources/main.swift' && grep -q 'Config.value(\"welcomed\") != Main.setup' '$APP/Sources/main.swift'"
check "and it can be asked for again"        "grep -q 'Show it again' '$APP/Sources/main.swift'"
check "it can say when a job is done"       \
    "grep -q 'enum Word' '$APP/Sources/main.swift' && grep -q 'UNUserNotificationCenter' '$APP/Sources/main.swift'"
check "but only for runs that changed something" \
    "grep -q 'arguments.contains(\\\"--yes\\\")' '$APP/Sources/main.swift'"
check "every page's buttons are one group of pictures" \
    "grep -q 'symbolic: Bool = true' '$APP/Sources/main.swift' && ! grep -q 'runButton' '$APP/Sources/main.swift'"
check "and every page says what its button does" \
    "[ \$(grep -c '^ *does: \\\"' '$APP/Sources/main.swift') = 9 ]"
# He asked for the dash gone from everything anybody reads.
check "nothing on screen is joined with a dash" \
    "! grep -qE '\"[^\"]*—[^\"]*\"' '$APP/Sources/main.swift'"
# The one thing the page is for is a button with the words on it, on its own
# at the end of the row; everything else the page can do is behind one button
# rather than a row of pictures nobody can tell apart.
check "the page ends on the thing it is for" \
    "grep -q 'primary.set(item.verb, live: !busy)' '$APP/Sources/main.swift'"
# A page that only reads has no button: opening it reads it, and Cmd-R reads
# it again. "Look again" beside a page that had just looked was a button for
# the sake of having one.
check "and only the pages that do something have one" \
    "grep -q 'let acts = item.asks != nil || !item.looksOnly' '$APP/Sources/main.swift'"
# The other things a page can do belong on the page, next to what they act on,
# with their names showing.
check "the rest are named, on the page"      \
    "grep -q 'func others()' '$APP/Sources/main.swift' && ! grep -q 'ellipsis' '$APP/Sources/main.swift'"
# Three ladders — the bars falling left to right, the colour falling with
# them, the table reading down — all handed the order the CLI printed in.
check "the breakdown is drawn biggest first"  \
    "grep -q 'named.sort { \$0.size > \$1.size }' '$APP/Sources/main.swift'"
# A name cut at nine letters gave "Screensho".
check "and a bar's name is cut by its width, not by a count" \
    "! grep -q 'part.name.prefix(9)' '$APP/Sources/main.swift'"
# The row was built once with whether Kliner was busy at that moment, and
# nothing held it, so it stayed grey and unclickable after the run finished.
check "the quiet actions come back when the run ends" \
    "grep -q 'private var offered: \\[Chip\\]' '$APP/Sources/main.swift' && grep -q 'private func wake()' '$APP/Sources/main.swift' && grep -q 'offered.append(chip)' '$APP/Sources/main.swift'"
# Reading a full disk takes tens of seconds, and for those seconds the first
# screen was a small grey shape in the corner of a dark rectangle, no words.
check "the waiting face is in the middle and says what it is doing" \
    "grep -q 'private func waitingWords()' '$APP/Sources/main.swift' && grep -q 'face.centerXAnchor.constraint(equalTo: holder.centerXAnchor)' '$APP/Sources/main.swift'"
# Everything on Home but one figure is instant; the junk figure walks every
# cache on the disk. Asking for the lot meant waiting for all of it.
check "doctor can answer its instant half alone" \
    "grep -q 'NIMO_FAST:-0' '$ROOT/lib/tools.sh' && bash '$MIN' doctor --fast -q --no-color | grep -q 'your computer'"
check "and home asks for that half first"    \
    "grep -q 'private var filling = false' '$APP/Sources/main.swift' && grep -q 'if filling { arguments += \[\"--fast\"\] }' '$APP/Sources/main.swift' && grep -q 'private func fillIn()' '$APP/Sources/main.swift'"
# The bars are the picture and the table is the reading. A stacked bar and a
# row of dots naming every kind again between them was one thing said thrice.
check "the breakdown is drawn twice, not three times" \
    "! sed -n '/private func drawBreakdown/,/^    }/p' '$APP/Sources/main.swift' | grep -q 'Split('"
# The card is named after the page already, so the panel's own heading printed
# again left "your desktop" sitting on its own under the table.
check "and the panel heading is not printed under it" \
    "sed -n '/private func drawBreakdown/,/^    }/p' '$APP/Sources/main.swift' | grep -q 'if whole > 0 { break }'"
# At a fifth of the label colour on a barely-there disc he read as a smudge.
check "the corner reads as somebody, not a smudge" \
    "grep -q 'face.contentTintColor = Paint.ink' '$APP/Sources/main.swift'"
# The row of buttons sits opposite the page title, not underneath it, so one
# line across the top says what the page is and what it can do.
# One row across the top holds everything that is not the page. The page under
# it is only the page.
check "and the row lives in the top bar"     \
    "grep -q 'buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor' '$APP/Sources/main.swift' && grep -q 'buttons.centerYAnchor.constraint(equalTo: chrome.centerYAnchor)' '$APP/Sources/main.swift'"
# Pinning a view to the far edge of something inside it is a loop: the row is
# placed by its contents and its contents are placed by the row. Auto Layout
# does not crash on it, it quietly throws constraints away, and half the
# window comes out missing. That shipped once.
check "nothing is pinned to its own contents" \
    "python3 '$ROOT/tools/loopcheck.py' '$APP/Sources/main.swift'"
# `let way = NSStackView()` at the top of a function and `let way: CGFloat` at
# the bottom of the same one is a compile error, and it is invisible when the
# two are four hundred lines apart. That cost a build.
check "and no name is declared twice in one scope" \
    "python3 '$ROOT/tools/shadow.py' '$APP/Sources/main.swift'"
check "and the trail never says the same word twice" \
    "grep -q 'trail(place == name ? \"Kliner\" : place, name)' '$APP/Sources/main.swift'"
# The name of the page is in that row, on the same line as everything you can
# do to it, and there is no second copy of it below.
check "the page's name is in the row as well" \
    "grep -q 'titleLabel.centerYAnchor.constraint(equalTo: chrome.centerYAnchor)' '$APP/Sources/main.swift'"
# Written as a trail: where you are, in the place it belongs, one label and
# two weights so it reads as one line.
check "and it says where that page belongs"  \
    "grep -q 'func trail(' '$APP/Sources/main.swift' && grep -q 'titleLabel.set(line, more:' '$APP/Sources/main.swift'"
# A tab, not a caption: the page you are on is a thing standing in the row
# along the top, at the left edge of the page it names. Centred in the row it
# read as a window title, which is what the title bar behind it already is.
check "the page's name is a tab at the left edge of the page" \
    "grep -q 'titleCentre = titleLabel.leadingAnchor.constraint(equalTo: pane.leadingAnchor)' '$APP/Sources/main.swift' && grep -q 'titleCentre.priority = .defaultHigh' '$APP/Sources/main.swift'"
check "and the tab carries the mark of the place it is in" \
    "grep -q 'func wear(_ symbol: String)' '$APP/Sources/main.swift' && grep -q 'titleLabel.wear(Action.place(of: chosen)?.symbol' '$APP/Sources/main.swift'"
# In a window too narrow to have a middle the want gives way and the name goes
# back to starting where the page starts, rather than printing over a button.
check "and it never prints over a button"    \
    "grep -q 'titleLeading.priority = .defaultLow' '$APP/Sources/main.swift' && grep -q 'titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: chrome.trailingAnchor' '$APP/Sources/main.swift'"
# The page you are on is marked once, in the one colour the window has. A
# grey pill as well says in a second way what the darker word already says.
check "the list marks where you are in Kliner's colour" \
    "grep -q 'if chosen { background = Paint.wash }' '$APP/Sources/main.swift'"
check "and not with a grey box as well" \
    "! grep -q 'if chosen { background = Paint.picked }' '$APP/Sources/main.swift'"
check "paragraphs have room between their lines" \
    "grep -q 'lineHeightMultiple' '$APP/Sources/main.swift' && grep -q 'func leaded' '$APP/Sources/main.swift'"
check "and the work stops at a readable width" \
    "grep -q 'static let column: CGFloat' '$APP/Sources/main.swift' && grep -q 'lessThanOrEqualToConstant: Main.column' '$APP/Sources/main.swift'"
# The row along the top takes no colour of its own: it is the glass above the
# card, with the three lights in it. Two hairlines used to be drawn to say
# where the list stopped and where the page's words started; the card has an
# edge of its own, and two lines saying one thing is one line too many.
check "the page begins under the row along the top" \
    "grep -q 'pane.topAnchor.constraint(equalTo: content.topAnchor,' '$APP/Sources/main.swift' \
     && grep -q 'constant: Step.bar + Step.air)' '$APP/Sources/main.swift'"
# Under the card, on the glass: what Kliner is doing, and the way to ask
# again. It is the difference between an app quietly doing something and an
# app that has stopped.
check "there is a line under the card that says what it is doing" \
    "grep -q 'final class Strip: NSView' '$APP/Sources/main.swift' \
     && grep -q 'strip.topAnchor.constraint(equalTo: pane.bottomAnchor)' '$APP/Sources/main.swift' \
     && grep -q 'private func tellStrip()' '$APP/Sources/main.swift'"
check "and the dot on it breathes while it reads" \
    "grep -q 'pulse.autoreverses = true' '$APP/Sources/main.swift'"
check "and the card's own edge is the only line drawn" \
    "grep -q 'edge.fillColor = .clear' '$APP/Sources/main.swift' \
     && grep -q 'under.fillColor = .clear' '$APP/Sources/main.swift'"
# The list is not on the card. The card is the page.
check "the list stands on the glass, not on the page" \
    "grep -q 'under.leadingAnchor.constraint(equalTo: pane.leadingAnchor)' '$APP/Sources/main.swift' \
     && grep -q 'stack.leadingAnchor.constraint(equalTo: content.leadingAnchor' '$APP/Sources/main.swift'"
check "and the setup keeps the one down the side" \
    "grep -q 'railLine?.isHidden = false' '$APP/Sources/main.swift' && grep -q 'barLine, chrome' '$APP/Sources/main.swift'"
check "with no second line inside the row" \
    "! grep -q 'split.widthAnchor.constraint(equalToConstant: 1)' '$APP/Sources/main.swift'"
# Home is a list of things to do, not four numbers and a shrug.
check "home says what to do about it"        \
    "grep -q 'final class Job' '$APP/Sources/main.swift' && grep -q 'let list = Card(\"What to do\")' '$APP/Sources/main.swift'"
check "and pressing one starts it"           \
    "grep -q 'func startOn' '$APP/Sources/main.swift'"
check "a page can be asked again"            \
    "grep -q 'func refresh' '$APP/Sources/main.swift' && grep -q 'keyEquivalent: \"r\"' '$APP/Sources/main.swift'"
check "and the introduction shown again"     \
    "grep -q 'func replaySetup' '$APP/Sources/main.swift' && grep -A1 'Show the introduction' '$APP/Sources/main.swift' | grep -q 'keyEquivalent: \"f\"'"
# Two arcs crossing on a shape is something turning over; one arc going round
# is a spinner wearing a costume.
check "the waiting has two arcs, not one"    \
    "grep -q 'private let trail = CAShapeLayer()' '$APP/Sources/main.swift' && grep -q 'send(trail, length: 0.34' '$APP/Sources/main.swift'"
# A face that is thinking keeps time. It used to wait a random number of
# seconds and then run a random sequence, which reads as a thing twitching.
check "and the face waiting keeps time"      \
    "grep -q 'static let turn: \\[(String, Double)\\]' '$APP/Sources/main.swift' && ! sed -n '/^final class Thinking/,/^}/p' '$APP/Sources/main.swift' | grep -q 'random'"
# Up and down walk the list, which is the last thing in the window that only
# a mouse could reach.
check "the list answers the arrow keys"      \
    "grep -q 'func walkList' '$APP/Sources/main.swift' && grep -q 'case 125:' '$APP/Sources/main.swift'"
check "but not while something is being typed into" \
    "grep -q 'firstResponder is NSTextView' '$APP/Sources/main.swift'"
# The outline is drawn at the size the face is drawn, so a face that scales is
# a face that leaves its own outline behind.
check "the waiting face does not shrink out of its outline" \
    "! sed -n '/^final class Thinking/,/^}/p' '$APP/Sources/main.swift' | grep -q 'transform.scale'"
# He does the waiting in the middle of the page and then goes and sits in the
# corner, so the thing that was working and the thing you hand work to are
# plainly the same thing.
check "Kliner sits in the corner of the page" \
    "grep -q 'final class Helper' '$APP/Sources/main.swift' && grep -q 'func settleHelper' '$APP/Sources/main.swift' && grep -q 'helper.land(from: middle)' '$APP/Sources/main.swift'"
check "and you can give him something to do"  \
    "grep -q 'func jobs()' '$APP/Sources/main.swift' && grep -q 'Give Kliner something to do' '$APP/Sources/main.swift'"
check "all of it at once asks once, for the lot" \
    "grep -q 'func doThemAll' '$APP/Sources/main.swift' && grep -q 'messageText = \"Do all of it?\"' '$APP/Sources/main.swift'"
check "and it ends back where it was asked for" \
    "grep -q 'ran = false' '$APP/Sources/main.swift' && grep -A6 'guard ran else' '$APP/Sources/main.swift' | grep -q 'self.show(0)'"
check "and works through them one page at a time" \
    "grep -q 'func nextInQueue' '$APP/Sources/main.swift' && grep -q 'func carryOn' '$APP/Sources/main.swift'"
# Opening a page starts a run of its own, the preview, and `run` drops
# anything asked for while one is going. So a press on a task was swallowed:
# the page changed and nothing happened.
check "a press waits its turn instead of being dropped" \
    "grep -q 'private func once(' '$APP/Sources/main.swift' && grep -A8 'func startOn' '$APP/Sources/main.swift' | grep -q 'once {'"
# He flies in from wherever the waiting was, so he only flies when there was
# one. Home reading itself every half minute is not an arrival to watch.
check "and he only flies in when he was waiting" \
    "grep -q 'waited = !quietly' '$APP/Sources/main.swift' && grep -q 'guard waited, !welcoming' '$APP/Sources/main.swift'"
# A list belonging to something at the bottom of a window has to open upwards,
# or it opens off the window and over the desktop.
check "a list opens where there is room for it" \
    "grep -q 'var side = NSRectEdge.minY' '$APP/Sources/main.swift' && grep -q 'preferredEdge: side' '$APP/Sources/main.swift'"
check "a click cannot be eaten by the picture inside a button" \
    "[ \$(grep -c 'override func hitTest' '$APP/Sources/main.swift') -ge 6 ]"
check "there is a way to search from the keyboard" \
    "grep -q 'final class Seek' '$APP/Sources/main.swift' && grep -q 'keyEquivalent: \"k\"' '$APP/Sources/main.swift'"
check "and typing narrows the list rather than covering it" \
    "grep -q 'func sieve' '$APP/Sources/main.swift' && grep -q 'row.isHidden = !(want.isEmpty || found)' '$APP/Sources/main.swift'"
# The list is five places, not nine pages. Walking Action.all through rows[i]
# ran off the end of a seven-row list on the first letter typed.
check "and it narrows the rows there are, not the pages there are" \
    "! grep -q 'rows\\[i\\]' '$APP/Sources/main.swift' && grep -q 'guard let place = Action.place(of: row.index)' '$APP/Sources/main.swift'"
# The setup used to empty the button row and never fill it again, so every
# page after the introduction had no button on it for the rest of the session.
check "the setup never empties the button row" \
    "! grep -q 'for view in buttons.arrangedSubviews' '$APP/Sources/main.swift'"
# A face made as the argument to the call that places it has no window yet.
check "the waiting face starts blinking once it has a window" \
    "sed -n '/^final class Thinking/,/^}/p' '$APP/Sources/main.swift' | grep -q 'override func viewDidMoveToWindow'"
# One thing in the corner of the row, and it holds everything that used to be
# spread along it: what this page can do, what Kliner has done, and the keys.
check "Kliner holds the rest of it"          \
    "grep -q 'func here()' '$APP/Sources/main.swift' && grep -q 'func keys()' '$APP/Sources/main.swift'"
check "and one list holds all three"          \
    "grep -q 'static func over(' '$APP/Sources/main.swift' && grep -q 'Sheet.Line.over(\"Recently\")' '$APP/Sources/main.swift'"
# One Kliner. He was in the corner of the top row and in the corner of the
# page at the same time, which is two of him.
check "there is one Kliner, and he holds the dot" \
    "! grep -q 'class Bell' '$APP/Sources/main.swift' && grep -q 'self.helper.unread = true' '$APP/Sources/main.swift'"
check "and looking at him puts it out"       \
    "grep -A1 'func showActivity' '$APP/Sources/main.swift' | grep -q 'helper.unread = false'"
# Swift will not reorder labelled arguments for you. Since nothing here can
# compile Swift, read the initialisers out of the source and check every call
# site against them by hand.
check "every call names its arguments in the order they are declared" \
    "python3 '$ROOT/tools/argorder.py' '$APP/Sources/main.swift'"
# The waiting ring traces the artwork's own outline. Both the outline and how
# far it reaches are read out of the file, because an outline somebody typed
# is an outline that drifts away from the drawing, and one measured down the
# image instead of up it is the drawing upside down.
check "the waiting ring is the shape in the drawing" \
    "python3 '$ROOT/tools/outline.py' '$ROOT/assets/app/outline.png' '$APP/Sources/main.swift'"
check "and it lies on the face, not around it" \
    "grep -q 'Thinking.path(around: middle, size: Thinking.across)' '$APP/Sources/main.swift'"
# Once a page has been read, coming back to it draws what it said. Walking a
# home folder again to be told the same thing is the app wasting your time.
check "a page you have already opened is not run again" \
    "grep -q 'if let already = kept\\[index\\]' '$APP/Sources/main.swift'"
check "and what it said is what comes back"  \
    "grep -q 'self.kept\\[asked\\] = pieces' '$APP/Sources/main.swift'"
# The same cards on every page, so moving between them is moving between
# pages of one thing.
check "every page is built out of the same cards" \
    "grep -q 'func put(_ view: NSView' '$APP/Sources/main.swift' && grep -q 'card = Card(title)' '$APP/Sources/main.swift'"
# Every page, not only the ones reporting on the machine: how many of whatever
# it lists, how much room they take, and which one is the biggest.
check "and every page puts its figures on top" \
    "grep -q 'func stats(_ pieces' '$APP/Sources/main.swift' && grep -q 'for box in stats(pieces)' '$APP/Sources/main.swift'"
check "and every page says what one of its rows is" \
    "[ \$(grep -c '^ *counts: \"' '$APP/Sources/main.swift') = 8 ]"
# Every panel in the window is the same panel: same corner, same hairline,
# same fill, same air inside it.
check "every panel in the window is the same panel" \
    "grep -q 'enum Panel {' '$APP/Sources/main.swift' && [ \$(grep -c 'Panel.dress(self)' '$APP/Sources/main.swift') -ge 2 ]"
check "and none of them names its own corner" \
    "! grep -qE 'layer\\?.cornerRadius = 1[024]$' '$APP/Sources/main.swift'"
# The eyes move, not the mark. A layer slid sideways is the whole word walking.
check "only the eyes look sideways"          \
    "! sed -n '/^final class Wordmark/,/^}/p' '$APP/Sources/main.swift' | grep -q 'transform' && grep -q '\"-right\"' '$APP/Sources/main.swift'"
check "and the frames are drawn from the art" \
    "python3 '$ROOT/tools/glance.py' '$APP/Resources' >/dev/null"
# Proved by the pixels: the looking frames differ from the one they came from
# in one small place near the top, and nowhere else.
check "proved by the pixels, not by the name" \
    "python3 '$ROOT/tools/glance.py' '$APP/Resources' --check"
check "the meter fills rather than appearing filled" \
    "grep -q 'forKey: \"filling\"' '$APP/Sources/main.swift'"
# The way to find a page belongs with the pages.
# The way to find a page belongs with the pages. In the row along the top it
# sat between the chrome and the name of the page, which is nothing to do with
# either.
check "the search field lives with the list" \
    "grep -q 'stack.addArrangedSubview(seek)' '$APP/Sources/main.swift' && grep -q 'search.isHidden = narrow' '$APP/Sources/main.swift'"
# Lists drawn by Kliner, not handed to the menu server: the same rows,
# hairlines and fills as everything else in the window.
check "the lists that open are drawn here"   \
    "grep -q 'enum Sheet {' '$APP/Sources/main.swift' && ! grep -q 'menu.popUp' '$APP/Sources/main.swift'"
# The trail is already the way to switch pages inside a place. A second
# control saying the same thing beside it is one control too many.
check "and there is one way to switch, not two" \
    "grep -q 'Sheet.open(lines, under: titleLabel' '$APP/Sources/main.swift' && ! grep -q 'pagePill' '$APP/Sources/main.swift'"
# One colour, not two: with the list hidden but the rail where it was, the
# setup was a wide dark page beside a strip of a different dark.
# It used to fold the rail away and take the whole window, which is a
# different app for four pages and then yours.
check "the setup keeps the window it is in"  \
    "grep -q 'railWidth.constant = narrow && !yes ? 70 : 246' '$APP/Sources/main.swift'"
# A line between the name of a figure and the figure is a line between a thing
# and itself.
check "a figure is not fenced off from its name" \
    "! grep -q 'rule.topAnchor.constraint(equalTo: under.bottomAnchor' '$APP/Sources/main.swift'"
check "with the whole of it faint behind it" \
    "grep -q 'private let track = CAShapeLayer()' '$APP/Sources/main.swift'"
check "and a preview can never be given --yes" \
    "! grep -qE 'preview.*--yes|--yes.*preview' '$APP/Sources/main.swift'"
# Every Action literal must carry a symbol, or a row down the side is blank.
NAKED=$(awk '
    /Action\(title:/ { inside = 1; got = 0; name = $0 }
    inside && /symbol:/ { got = 1 }
    inside && /\),?$/ && /symbol:|reveal:|walks:|looksOnly:|symbolic:|group:/ {
        if (got) { inside = 0 } }
    inside && /^ *Action\(title:/ && NR > 1 { }
    inside && /^\s*$/ { if (!got) print name; inside = 0 }
    END { }' "$APP/Sources/main.swift")
check "every row down the side has a picture" "[ -z '$NAKED' ]"
check "ci builds the app"                 "grep -q 'app/build.sh' '$ROOT/.github/workflows/ci.yml'"
check "the release carries the app"       "grep -q 'Kliner.app.zip' '$ROOT/.github/workflows/release.yml'"
check "the site points at the release"    "grep -q 'releases/latest/download/Kliner.app.zip' '$ROOT/docs/index.html'"

# ---- verdict ------------------------------------------------------------

printf '\n'
if [ "$FAIL" -eq 0 ]; then
    printf '  %s✓ %d passed%s\n\n' "$G" "$PASS" "$Z"
    exit 0
else
    printf '  %s%d passed, %d failed%s%s\n\n' "$R" "$PASS" "$FAIL" "$FAILED" "$Z"
    exit 1
fi
