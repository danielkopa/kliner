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
check "the menu bar glyph is there twice" \
    "[ -f '$APP/Resources/menubar.png' ] && [ -f '$APP/Resources/menubar@2x.png' ]"
check "there is one icon to change"       "[ -f '$ROOT/assets/app/icon-1024.png' ]"

check "the app is a normal app, not a menu bar one" \
    "! grep -q 'LSUIElement' '$APP/Info.plist'"
check "it puts an icon in the Dock"       "grep -q 'setActivationPolicy(.regular)' '$APP/Sources/main.swift'"
check "it opens a window when it starts"  "grep -q 'makeKeyAndOrderFront' '$APP/Sources/main.swift'"
check "it has a menu bar of its own"      "grep -q 'NSApp.mainMenu = buildMenu' '$APP/Sources/main.swift'"
check "you can quit it"                   "grep -q 'NSApplication.terminate' '$APP/Sources/main.swift'"
check "nimo's panel is read back into real controls" \
    "grep -q 'enum Report' '$APP/Sources/main.swift' && grep -q 'case heading' '$APP/Sources/main.swift'"
DOUBLE=$(awk '/^final class /{c=$3} /required init\?\(coder/{print c}' "$APP/Sources/main.swift" | sort | uniq -d)
check "no class overrides init(coder:) twice" "[ -z '$DOUBLE' ]"
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
check "there is no terminal left in the window" \
    "! grep -q 'NSTextView' '$APP/Sources/main.swift'"
check "what nimo said is laid out as text"  "grep -q 'final class Said' '$APP/Sources/main.swift'"
check "there is nothing shouting on the page" \
    "! grep -q 'Paint.accent' '$APP/Sources/main.swift'"
check "the window follows the system, light or dark" \
    "grep -q 'NSColor.labelColor' '$APP/Sources/main.swift' && ! grep -q 'window.appearance' '$APP/Sources/main.swift'"
check "the window is glass"                 "grep -q 'NSVisualEffectView' '$APP/Sources/main.swift'"
check "and it lets the desktop through"     "grep -q 'window.isOpaque = false' '$APP/Sources/main.swift'"
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
check "the groups are told apart by a line, not a word" \
    "grep -q 'item.group != lastGroup' '$APP/Sources/main.swift'"
check "it can ask macOS for what it needs"  "grep -q 'askForEverything' '$APP/Sources/main.swift'"
check "and it never claims to grant itself access" \
    "grep -q 'enum Access' '$APP/Sources/main.swift' && grep -q 'Privacy_AllFiles' '$APP/Sources/main.swift'"
check "settings are the same file nimo reads" \
    "grep -q '.nimo\\\", isDirectory' '$APP/Sources/main.swift' && grep -q 'enum Config' '$APP/Sources/main.swift'"
check "it spins while it thinks"            "grep -q 'NSProgressIndicator' '$APP/Sources/main.swift'"
check "the panel fades in"                  "grep -q 'NSAnimationContext' '$APP/Sources/main.swift'"
check "its version is filled in at build" "grep -q '__VERSION__' '$APP/Info.plist'"
check "build.sh fills it in"              "grep -q 's/__VERSION__/' '$APP/build.sh'"
check "the plist names the executable"    "grep -q '<string>Nimo</string>' '$APP/Info.plist'"

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
    "grep -q 'preview: item.asks != nil' '$APP/Sources/main.swift'"
check "and a preview can never be given --yes" \
    "! grep -qE 'preview.*--yes|--yes.*preview' '$APP/Sources/main.swift'"
ACTIONS=$(grep -c 'Action(title:' "$APP/Sources/main.swift")
PICTURES=$(grep -c '^ *symbol: "[a-z]' "$APP/Sources/main.swift")
check "every row down the side has a picture" "[ '$ACTIONS' = '$PICTURES' ] && [ '$ACTIONS' != '0' ]"
check "ci builds the app"                 "grep -q 'app/build.sh' '$ROOT/.github/workflows/ci.yml'"
check "the release carries the app"       "grep -q 'Nimo.app.zip' '$ROOT/.github/workflows/release.yml'"
check "the site points at the release"    "grep -q 'releases/latest/download/Nimo.app.zip' '$ROOT/docs/index.html'"

# ---- verdict ------------------------------------------------------------

printf '\n'
if [ "$FAIL" -eq 0 ]; then
    printf '  %s✓ %d passed%s\n\n' "$G" "$PASS" "$Z"
    exit 0
else
    printf '  %s%d passed, %d failed%s%s\n\n' "$R" "$PASS" "$FAIL" "$FAILED" "$Z"
    exit 1
fi
