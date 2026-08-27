#!/usr/bin/env bash
#
#   nimo's macOS suite.
#
#       bash test/macos.sh
#
#   The dock, the wallpaper and the preferences are the parts of nimo that
#   only ever run on a Mac, which used to mean they were the parts nobody
#   could test. This suite stands in fake `defaults`, `osascript`, `killall`,
#   `sw_vers`, `pmset`, `sqlite3` and `uname` in front of the real ones and
#   runs the real nimo code against them, on any machine.
#
#   It never touches a real dock, a real wallpaper or a real preference.
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

BOX=$(mktemp -d "${TMPDIR:-/tmp}/nimo-macos.XXXXXX") || exit 1
trap 'rm -rf "$BOX"' EXIT INT TERM

FAKE="$BOX/fakebin"
STATE="$BOX/state"
mkdir -p "$FAKE" "$STATE"

DOCK="$STATE/dock"                 # one app url per line
WROTE="$STATE/defaults-writes"     # every plain `defaults write`
PREFS="$STATE/prefs"               # domain<TAB>key<TAB>type<TAB>value
SCRIPTED="$STATE/osascript"        # every osascript that ran
SQL="$STATE/sqlite"                # the last resort wallpaper path
: > "$WROTE"; : > "$SCRIPTED"; : > "$SQL"; : > "$PREFS"

cat > "$FAKE/uname" <<'SHIM'
#!/bin/sh
case "${1:-}" in
    -s) echo Darwin ;;
    -m) echo arm64 ;;
    -r) echo 24.5.0 ;;
    *)  echo Darwin ;;
esac
SHIM

cat > "$FAKE/sw_vers" <<'SHIM'
#!/bin/sh
case "${1:-}" in
    -productName)    echo macOS ;;
    -productVersion) echo 15.5 ;;
    *)               echo "ProductName: macOS" ;;
esac
SHIM

cat > "$FAKE/pmset" <<'SHIM'
#!/bin/sh
echo "Now drawing from 'Battery Power'"
echo " -InternalBattery-0 (id=12345)	87%; discharging; 4:12 remaining present: true"
SHIM

cat > "$FAKE/killall" <<'SHIM'
#!/bin/sh
exit 0
SHIM

cat > "$FAKE/launchctl" <<SHIM
#!/bin/sh
echo "\$*" >> "$STATE/launchctl"
exit 0
SHIM

# A `defaults` that is real enough for nimo, and only for nimo.
cat > "$FAKE/defaults" <<SHIM
#!/bin/sh
DOCK="$DOCK"
WROTE="$WROTE"
PREFS="$PREFS"
SHIM
cat >> "$FAKE/defaults" <<'SHIM'
verb="${1:-}"; shift 2>/dev/null || true

case "$verb" in
    read)
        domain="${1:-}"; key="${2:-}"
        if [ -n "$key" ] && [ "$key" != "persistent-apps" ]; then
            line=$(grep "^$domain	$key	" "$PREFS" | tail -1)
            [ -n "$line" ] || exit 1
            printf '%s\n' "$line" | cut -f4
            exit 0
        fi
        if [ "$domain" = "com.apple.dock" ] && [ "$key" = "persistent-apps" ]; then
            [ -s "$DOCK" ] || exit 1
            echo "("
            while IFS= read -r url; do
                [ -n "$url" ] || continue
                echo "        {"
                echo "        \"file-data\" =         {"
                echo "            \"_CFURLString\" = \"$url\";"
                echo "            \"_CFURLStringType\" = 15;"
                echo "        };"
                echo "        \"tile-type\" = \"file-tile\";"
                echo "    },"
            done < "$DOCK"
            echo ")"
            exit 0
        fi
        exit 1
        ;;
    write)
        domain="${1:-}"; key="${2:-}"; shift 2 2>/dev/null || true
        if [ "$domain" = "com.apple.dock" ] && [ "$key" = "persistent-apps" ]; then
            case "${1:-}" in
                -array)
                    : > "$DOCK"
                    exit 0 ;;
                -array-add)
                    printf '%s\n' "$2" \
                        | sed -n 's/.*<string>\(file:[^<]*\)<\/string>.*/\1/p' >> "$DOCK"
                    exit 0 ;;
            esac
            exit 0
        fi
        echo "$domain $key $*" >> "$WROTE"
        type="string"
        case "${1:-}" in
            -bool)   type="boolean" ;;
            -int)    type="integer" ;;
            -float)  type="float" ;;
            -string) type="string" ;;
        esac
        case "${1:-}" in
            -*) value="${2:-}" ;;
            *)  value="${1:-}" ;;
        esac
        grep -v "^$domain	$key	" "$PREFS" > "$PREFS.new" 2>/dev/null || true
        mv "$PREFS.new" "$PREFS" 2>/dev/null || true
        printf '%s\t%s\t%s\t%s\n' "$domain" "$key" "$type" "$value" >> "$PREFS"
        exit 0
        ;;
    read-type)
        domain="${1:-}"; key="${2:-}"
        line=$(grep "^$domain	$key	" "$PREFS" | tail -1)
        [ -n "$line" ] || exit 1
        echo "Type is $(printf '%s\n' "$line" | cut -f3)"
        exit 0
        ;;
    delete)
        domain="${1:-}"; key="${2:-}"
        grep -v "^$domain	$key	" "$PREFS" > "$PREFS.new" 2>/dev/null || true
        mv "$PREFS.new" "$PREFS" 2>/dev/null || true
        echo "DELETED $domain $key" >> "$WROTE"
        exit 0
        ;;
    export)
        domain="${1:-}"; file="${2:-}"
        [ "$domain" = "com.apple.dock" ] || exit 1
        cp "$DOCK" "$file" 2>/dev/null || exit 1
        exit 0
        ;;
    import)
        domain="${1:-}"; file="${2:-}"
        [ "$domain" = "com.apple.dock" ] || exit 1
        cp "$file" "$DOCK" 2>/dev/null || exit 1
        exit 0
        ;;
esac
exit 0
SHIM

# osascript records what it was asked to do; NIMO_OSA_FAIL makes it refuse,
# the way macOS does when Automation permission has not been granted.
cat > "$FAKE/osascript" <<SHIM
#!/bin/sh
SCRIPTED="$SCRIPTED"
LOGIN="$STATE/login-items"
WALL="$STATE/wallpaper"
SHIM
cat >> "$FAKE/osascript" <<'SHIM'
shift 2>/dev/null || true
printf '%s\n' "$*" >> "$SCRIPTED"

# The login items, kept one per line as  name<TAB>path , and answered the way
# AppleScript answers a list: "a, b, c" on one line.
case "$*" in
    *"name of every login item"*)
        [ -s "$LOGIN" ] || exit 0
        cut -f1 "$LOGIN" | paste -sd, - | sed 's/,/, /g'
        exit 0 ;;
    *"path of every login item"*)
        [ -s "$LOGIN" ] || exit 0
        cut -f2 "$LOGIN" | paste -sd, - | sed 's/,/, /g'
        exit 0 ;;
    *"delete login item"*)
        want=$(printf '%s' "$*" | sed -n 's/.*delete login item "\([^"]*\)".*/\1/p')
        [ -n "$want" ] || exit 1
        w="$want" awk -F'\t' '$1 != ENVIRON["w"]' "$LOGIN" > "$LOGIN.new"
        mv "$LOGIN.new" "$LOGIN"
        exit 0 ;;
    *"make login item"*)
        p=$(printf '%s' "$*" | sed -n 's/.*path:"\([^"]*\)".*/\1/p')
        [ -n "$p" ] || exit 1
        n=$(basename "$p"); n="${n%.app}"
        printf '%s\t%s\n' "$n" "$p" >> "$LOGIN"
        exit 0 ;;
esac

# The wallpaper this pretend Mac is actually showing. It has to be
# remembered rather than made up, because nimo reads it back to check that
# setting it worked — Apple's own AppleScript returns success on some
# systems while changing nothing, so "it did not error" is not enough.
case "$*" in
    *"get desktop picture"*)
        [ "${NIMO_OSA_FAIL:-0}" = "1" ] && exit 1
        cat "$WALL" 2>/dev/null
        exit 0 ;;
    *"set picture to POSIX file"*|*"set desktop picture to POSIX file"*)
        [ "${NIMO_OSA_FAIL:-0}" = "1" ] && exit 1
        # NIMO_OSA_LIES is the Sonoma bug itself: says yes, changes nothing
        [ "${NIMO_OSA_LIES:-0}" = "1" ] && exit 0
        printf '%s\n' "$*" | sed -n 's/.*POSIX file "\([^"]*\)".*/\1/p' > "$WALL"
        exit 0 ;;
esac
[ "${NIMO_OSA_FAIL:-0}" = "1" ] && exit 1
exit 0
SHIM

cat > "$FAKE/sqlite3" <<SHIM
#!/bin/sh
SQL="$SQL"
SHIM
cat >> "$FAKE/sqlite3" <<'SHIM'
printf '%s\n' "$*" >> "$SQL"
exit 0
SHIM

chmod +x "$FAKE"/*

# a home that looks like a Mac
mkdir -p "$BOX/Library/Caches" "$BOX/Library/Logs" "$BOX/.Trash" \
         "$BOX/Desktop" "$BOX/Downloads" \
         "$BOX/Library/Application Support/Dock"
: > "$BOX/Library/Application Support/Dock/desktoppicture.db"
dd if=/dev/zero of="$BOX/Library/Caches/some-app-cache" bs=1024 count=9216 2>/dev/null
dd if=/dev/zero of="$BOX/.Trash/thrown-away" bs=1024 count=3072 2>/dev/null

printf '%s\n' \
    "file:///System/Applications/TV.app/" \
    "file:///System/Applications/Podcasts.app/" \
    "file:///Applications/Safari.app/" \
    "file:///Applications/Google%20Chrome.app/" \
    "file:///System/Applications/Utilities/Terminal.app/" > "$DOCK"

# empty stdin, for the same reason as in test/run.sh
mac() { PATH="$FAKE:$PATH" HOME="$BOX" bash "$MIN" "$@" </dev/null; }

printf '\n  %snimo macOS suite%s\n' "$B" "$Z"
printf '  %sreal nimo code, fake macOS underneath · %s%s\n\n' "$D" "$BOX" "$Z"

# ---- is nimo even convinced this is a Mac? ------------------------------

check "nimo believes it is on macOS"      "mac doctor -q --no-color | grep -q 'macOS 15.5'"
check "doctor reads the battery"          "mac doctor -q --no-color | grep -q '87%'"
check "doctor knows it is unplugged"      "mac doctor -q --no-color | grep -q 'on battery'"

# The bug this replaced: "discharging" contains "charging", so a battery on
# its way down was reported as plugged in. One case per state, so it stays fixed.
battery_says() {
    cat > "$FAKE/pmset" <<PMSET
#!/bin/sh
echo "Now drawing from '$1'"
echo " -InternalBattery-0 (id=12345)	$2%; $3; 4:12 remaining present: true"
PMSET
    chmod +x "$FAKE/pmset"
    mac doctor -q --no-color | sed -n 's/.*Battery *//p'
}

check "discharging is not 'plugged in'"   "[ \"\$(battery_says 'Battery Power' 64 discharging)\" = '64%  ·  on battery' ]"
check "charging reads as charging"        "[ \"\$(battery_says 'AC Power' 41 charging)\" = '41%  ·  charging' ]"
check "a full battery reads as charged"   "[ \"\$(battery_says 'AC Power' 100 charged)\" = '100%  ·  charged' ]"
battery_says 'Battery Power' 87 discharging >/dev/null
check "the macOS scan targets load"       "mac preview -q --no-color | grep -q 'App caches'"

# ---- the dock ------------------------------------------------------------

check "reads every app in the dock"       "[ \$(mac dock --list -q --no-color | grep -c 'app$\\|Safari\\|Terminal\\|TV\\|Podcasts\\|Chrome') -ge 5 ]"
check "decodes %20 in app names"          "mac dock --list -q --no-color | grep -q 'Google Chrome'"
check "marks what Apple put there"        "mac dock --list -q --no-color | grep -q 'TV.*came with macOS'"
check "does not mark apps you installed"  "! mac dock --list -q --no-color | grep 'Safari' | grep -q 'came with'"
check "--list changes nothing"            "[ \$(grep -c . '$DOCK') -eq 5 ]"

# tick the first two (TV, Podcasts) and confirm
printf ' \033[B \n' | PATH="$FAKE:$PATH" HOME="$BOX" NIMO_PICK_FORCE=1 \
    bash "$MIN" dock -y -q --no-color >/dev/null 2>&1

check "removes exactly what you ticked"   "[ \$(grep -c . '$DOCK') -eq 3 ]"
check "the ticked apps are gone"          "! grep -q 'TV.app' '$DOCK' && ! grep -q 'Podcasts.app' '$DOCK'"
check "everything else survived"          "grep -q 'Safari.app' '$DOCK' && grep -q 'Terminal.app' '$DOCK' && grep -q 'Chrome' '$DOCK'"
check "the order is preserved"            "[ \"\$(head -1 '$DOCK')\" = 'file:///Applications/Safari.app/' ]"
check "a backup was written first"        "ls '$BOX'/.nimo/backups/dock-*.plist >/dev/null 2>&1"

PATH="$FAKE:$PATH" HOME="$BOX" bash "$MIN" dock --restore -q --no-color >/dev/null 2>&1

check "--restore brings all five back"    "[ \$(grep -c . '$DOCK') -eq 5 ]"
check "--restore brings back the right ones" "grep -q 'TV.app' '$DOCK' && grep -q 'Podcasts.app' '$DOCK'"

# nothing ticked must mean nothing happens
printf '\n' | PATH="$FAKE:$PATH" HOME="$BOX" NIMO_PICK_FORCE=1 \
    bash "$MIN" dock -y -q --no-color >/dev/null 2>&1
check "ticking nothing leaves it alone"   "[ \$(grep -c . '$DOCK') -eq 5 ]"

# ---- the preferences -----------------------------------------------------

: > "$WROTE"
mac setup --dry-run -q --no-color >/dev/null 2>&1
check "setup --dry-run writes nothing"    "[ ! -s '$WROTE' ]"
check "setup --dry-run shows the commands" "mac setup --dry-run -q --no-color | grep -q 'defaults write com.apple.finder ShowPathbar'"

: > "$WROTE"
mac setup --only finder -y -q --no-color >/dev/null 2>&1
check "setup finder writes its keys"      "grep -q 'AppleShowAllExtensions' '$WROTE'"
check "setup finder sets list view"       "grep -q 'FXPreferredViewStyle' '$WROTE'"
check "setup finder stops .DS_Store"      "grep -q 'DSDontWriteNetworkStores' '$WROTE'"
check "setup finder leaves the dock be"   "! grep -q 'com.apple.dock autohide' '$WROTE'"

: > "$WROTE"
mac setup --only dock,keyboard -y -q --no-color >/dev/null 2>&1
check "setup takes two groups at once"    "grep -q 'com.apple.dock autohide' '$WROTE' && grep -q 'KeyRepeat' '$WROTE'"
check "and skips the ones not named"      "! grep -q 'screencapture' '$WROTE'"

: > "$WROTE"
mac setup -y -q --no-color >/dev/null 2>&1
check "setup with no group does them all" "[ \$(wc -l < '$WROTE') -ge 20 ]"
check "screenshots go to their own folder" "grep -q 'screencapture location' '$WROTE'"
check "nothing in setup calls sudo"       "! grep -q sudo '$WROTE'"

# ---- putting the preferences back ----------------------------------------
#
# setup used to be the one command with no way back, which made the promise
# on the tin false. It now writes down what every key was — including the
# ones that had never been set — before it touches anything.

fakedefaults() { PATH="$FAKE:$PATH" defaults "$@"; }

rm -rf "$BOX/.nimo/backups"
: > "$PREFS"; : > "$WROTE"

# one key already set by hand, the rest never touched
fakedefaults write com.apple.finder FXPreferredViewStyle -string clmv

mac setup --only finder -y -q --no-color >/dev/null 2>&1
LOG=$(ls -1 "$BOX"/.nimo/backups/setup-*.tsv 2>/dev/null | tail -1)

check "setup writes down what it changed"  "[ -s '$LOG' ]"
check "it records a key that existed"      "grep -q 'FXPreferredViewStyle	had	-string	clmv' '$LOG'"
check "it records keys that did not"       "grep -q 'AppleShowAllExtensions	absent' '$LOG'"
check "setup really did change the view"   "[ \"\$(fakedefaults read com.apple.finder FXPreferredViewStyle)\" = Nlsv ]"

: > "$WROTE"
mac setup --restore -q --no-color >/dev/null 2>&1

check "--restore puts the old value back"  "[ \"\$(fakedefaults read com.apple.finder FXPreferredViewStyle)\" = clmv ]"
check "--restore keeps the original type"  "fakedefaults read-type com.apple.finder FXPreferredViewStyle | grep -q string"
check "--restore unsets what was never set" "! fakedefaults read com.apple.finder ShowPathbar"
check "--restore says so in the log"        "grep -q 'DELETED com.apple.finder ShowPathbar' '$WROTE'"

check "booleans come back as booleans"     "fakedefaults write com.apple.dock autohide -bool false; mac setup --only dock -y -q --no-color >/dev/null 2>&1; mac setup --restore -q --no-color >/dev/null 2>&1; fakedefaults read-type com.apple.dock autohide | grep -q boolean"
check "and with the value they had"        "[ \"\$(fakedefaults read com.apple.dock autohide)\" = false ]"

# A value that is a whole structure cannot be replayed as one setting, so it
# must be marked and skipped rather than flattened into nonsense. This is the
# other half of the bug the guard above had.
record_of() {
    HOME="$BOX" bash -c '
        NIMO_VERSION=test
        for m in ui core; do . "'"$ROOT"'/lib/$m.sh"; done
        . "'"$ROOT"'/lib/setup.sh"
        # after sourcing, because setup.sh clears this on the way in
        NIMO_SETUP_LOG="$1"
        defaults() {
            case "$1" in
                read)      printf "line one\nline two\n" ;;
                read-type) echo "Type is string" ;;
            esac
        }
        nimo_setup_record com.example.app SomeKey' _ "$1"
}

MULTI="$BOX/multi.tsv"
: > "$MULTI"
record_of "$MULTI"
check "a structured value is not replayed"  "grep -q 'SomeKey	complex' '$MULTI'"
check "and a plain one still is"            "grep -q 'FXPreferredViewStyle	had' '$LOG'"

check "two runs in a second keep both logs" "mac setup --only keyboard -y -q --no-color >/dev/null 2>&1; mac setup --only dialogs -y -q --no-color >/dev/null 2>&1; [ \$(ls -1 '$BOX'/.nimo/backups/setup-*.tsv | wc -l) -ge 3 ]"

check "min undo lists the preferences too" "mac undo --list -q --no-color | grep -q 'changed preferences'"
check "min undo counts the settings"       "mac undo --list -q --no-color | grep -q 'settings'"

check "restoring twice is not an error"    "mac setup --restore -q --no-color >/dev/null 2>&1; mac setup --restore -q --no-color >/dev/null 2>&1"
rm -rf "$BOX/.nimo/backups"
check "nothing to restore says so calmly"  "mac setup --restore -q --no-color | grep -q 'has not changed any preferences'"

# ---- zen -----------------------------------------------------------------

rm -rf "$BOX/.nimo/backups"
: > "$PREFS"; : > "$WROTE"

check "zen hides the desktop icons"        "mac zen -y -q --no-color >/dev/null 2>&1; [ \"\$(fakedefaults read com.apple.finder CreateDesktop)\" = false ]"
check "zen writes down how to undo it"     "ls '$BOX'/.nimo/backups/setup-*.tsv >/dev/null 2>&1"
check "zen twice is not a problem"         "mac zen -y -q --no-color | grep -q 'already like that'"
check "zen --restore brings them back"     "mac zen --restore -y -q --no-color >/dev/null 2>&1; [ \"\$(fakedefaults read com.apple.finder CreateDesktop)\" = true ]"
check "zen --dry-run changes nothing"      "fakedefaults write com.apple.finder CreateDesktop -bool true; mac zen --dry-run -q --no-color >/dev/null 2>&1; [ \"\$(fakedefaults read com.apple.finder CreateDesktop)\" = true ]"
check "zen --dry-run shows the command"    "mac zen --dry-run -q --no-color | grep -q 'CreateDesktop -bool false'"

# ---- appearance and the menu bar -----------------------------------------

rm -rf "$BOX/.nimo/backups"
: > "$PREFS"; : > "$WROTE"; : > "$SCRIPTED"

check "dark asks the system to go dark"   "mac dark -y -q --no-color >/dev/null 2>&1; grep -q 'set dark mode to true' '$SCRIPTED'"
check "dark writes down what it was"      "ls '$BOX'/.nimo/backups/setup-*.tsv >/dev/null 2>&1"
check "dark records light as never set"   "grep -q 'AppleInterfaceStyle	absent' \$(ls -1 '$BOX'/.nimo/backups/setup-*.tsv | tail -1)"

fakedefaults write NSGlobalDomain AppleInterfaceStyle -string Dark
# Piping straight into grep -q would end this test early: grep exits on the
# first match and the command behind it dies of SIGPIPE before it has done
# anything. Whenever the command must finish, its output is captured first.
appearance_run() { mac light -y -q --no-color 2>&1; }

check "nimo can see it is dark now"       "[ -n \"\$(appearance_run | grep 'dark  →  light')\" ]"
check "light asks it to go back"          "grep -q 'set dark mode to false' '$SCRIPTED'"
check "asking for what you have is calm"  "fakedefaults write NSGlobalDomain AppleInterfaceStyle -string Dark; mac dark -y -q --no-color | grep -q 'already dark'"

: > "$SCRIPTED"
check "the fallback writes the pref"      "fakedefaults delete NSGlobalDomain AppleInterfaceStyle; NIMO_OSA_FAIL=1 PATH=\"$FAKE:\$PATH\" HOME=\"$BOX\" bash \"$MIN\" dark -y -q --no-color >/dev/null 2>&1 </dev/null; [ \"\$(fakedefaults read NSGlobalDomain AppleInterfaceStyle)\" = Dark ]"

: > "$PREFS"
check "hide tucks the menu bar away"      "mac hide -y -q --no-color >/dev/null 2>&1; [ \"\$(fakedefaults read NSGlobalDomain _HIHideMenuBar)\" = true ]"
check "hide twice is not a problem"       "mac hide -y -q --no-color | grep -q 'already like that'"
check "hide --restore brings it back"     "mac hide --restore -y -q --no-color >/dev/null 2>&1; [ \"\$(fakedefaults read NSGlobalDomain _HIHideMenuBar)\" = false ]"
check "hide --dry-run changes nothing"    "fakedefaults delete NSGlobalDomain _HIHideMenuBar; mac hide --dry-run -q --no-color >/dev/null 2>&1; ! fakedefaults read NSGlobalDomain _HIHideMenuBar"
check "hide --dry-run shows the command"  "mac hide --dry-run -q --no-color | grep -q '_HIHideMenuBar -bool true'"

# ---- apps you never open -------------------------------------------------

APPS="$BOX/Applications"
mkdir -p "$APPS/Forgotten.app/Contents" "$APPS/Daily.app/Contents"
dd if=/dev/zero of="$APPS/Forgotten.app/Contents/blob" bs=1024 count=4096 2>/dev/null
dd if=/dev/zero of="$APPS/Daily.app/Contents/blob" bs=1024 count=1024 2>/dev/null

cat > "$FAKE/mdls" <<'SHIM'
#!/bin/sh
# only ever asked for kMDItemLastUsedDate -raw <app>
case "$*" in
    *Forgotten.app*) echo "2019-03-04 11:02:00 +0000" ;;
    *Daily.app*)     printf '%s 09:00:00 +0000' "$(date +%Y-%m-%d)" ;;
    *)               echo "(null)" ;;
esac
SHIM
chmod +x "$FAKE/mdls"

apps_says() {
    PATH="$FAKE:$PATH" HOME="$BOX" bash -c '
        NIMO_VERSION=test
        for m in ui core pick scan clean setup desktop dock wall look dupes apps undo tools; do
            . "'"$ROOT"'/lib/$m.sh"
        done
        NIMO_QUIET=1; NIMO_COLOR=never; NIMO_LIMIT=15; NIMO_DAYS=180
        nimo_init_colors
        nimo_app_dirs() { printf "%s\n" "'"$APPS"'"; }
        nimo_cmd_apps' 2>&1
}

check "apps finds the forgotten one"      "apps_says | grep -q Forgotten"
check "apps leaves out what you use"      "! apps_says | grep -q Daily"
check "apps shows how big it is"          "apps_says | grep -q '4.0 MB'"
check "apps says when it was last opened" "apps_says | grep -q '2019-03-04'"
check "apps never uninstalls anything"    "apps_says >/dev/null; [ -d '$APPS/Forgotten.app' ]"
check "apps says so out loud"             "apps_says | grep -q 'does not uninstall'"

# ---- the wallpaper -------------------------------------------------------
#
# The list comes from paths that only exist on a real Mac, so this part
# sources nimo and points it at a folder of stand-ins instead.

PICS="$BOX/pics"
mkdir -p "$PICS/Solid Colors"
: > "$PICS/Sonoma Horizon.heic"
: > "$PICS/Ventura Graphic.heic"
: > "$PICS/Solid Colors/Black.png"

# mode: list | set | restore
wall() {
    PATH="$FAKE:$PATH" HOME="$BOX" NIMO_OSA_FAIL="${NIMO_OSA_FAIL:-0}" bash -c '
        NIMO_VERSION=test
        NIMO_QUIET=1
        NIMO_COLOR=never
        NIMO_LIMIT=15
        NIMO_DRY_RUN=0
        NIMO_RANDOM=0
        NIMO_LIST=0
        NIMO_RESTORE=0
        NIMO_ASSUME_YES=0
        case "$1" in
            list)    NIMO_LIST=1 ;;
            restore) NIMO_RESTORE=1 ;;
            set)     NIMO_ASSUME_YES=1 ;;
        esac
        for m in ui core pick scan clean setup desktop dock wall undo tools; do
            . "'"$ROOT"'/lib/$m.sh"
        done
        nimo_init_colors
        nimo_wall_dirs() { printf "%s\n" "'"$PICS"'" "'"$PICS"'/Solid Colors"; }
        nimo_cmd_wallpaper' _ "$1" 2>&1
}

printf '%s\n' "$PICS/Sonoma Horizon.heic" > "$STATE/wallpaper"
: > "$SCRIPTED"
LIST=$(wall list)
check "wallpaper lists what the mac has"   "printf '%s' \"\$LIST\" | grep -q 'Sonoma Horizon'"
check "wallpaper reaches into subfolders"  "printf '%s' \"\$LIST\" | grep -q 'Black'"
check "wallpaper marks its own pick"       "printf '%s' \"\$LIST\" | grep -q 'nimo would pick this one'"
check "--list sets nothing"                "[ ! -s '$SCRIPTED' ] || ! grep -q 'set picture to' '$SCRIPTED'"

OUT=$(wall set)
check "wallpaper prefers a solid colour"   "printf '%s' \"\$OUT\" | grep -q 'Wallpaper set — Black'"
check "wallpaper actually asked the system" "grep -q 'set picture to' '$SCRIPTED'"
check "it saved what you had before"       "grep -q 'Sonoma Horizon' '$BOX/.nimo/backups/wallpaper.txt'"

OUT=$(wall restore)
check "--restore puts the old one back"    "printf '%s' \"\$OUT\" | grep -q 'Wallpaper restored'"
check "--restore names the old wallpaper"  "printf '%s' \"\$OUT\" | grep -q 'Sonoma Horizon'"

: > "$SQL"
OUT=$(NIMO_OSA_FAIL=1 wall set)
check "falls back when macOS says no"      "[ -s '$SQL' ]"
check "the fallback nudges the Dock"       "grep -q 'desktoppicture' '$SQL' || grep -q 'update data set value' '$SQL'"

# ---- a tick nimo can stand behind ----------------------------------------
#
# Apple has moved the wallpaper three times, and the AppleScript that used to
# work still returns success on some systems while changing nothing at all.
# nimo used to print a tick on "osascript did not error", which is the worst
# thing a tool can do: you go looking for the fault in your own eyes.
#
# NIMO_OSA_LIES is that exact failure — every command succeeds and the
# wallpaper never moves.

WAS=$(cat "$STATE/wallpaper")
OUT=$(NIMO_OSA_LIES=1 wall set)
check "a lie is not reported as done"      "! printf '%s' \"\$OUT\" | grep -q 'Wallpaper set'"
check "and it says the Mac ignored it"     "printf '%s' \"\$OUT\" | grep -q 'did not'"
check "and where to look next"             "printf '%s' \"\$OUT\" | grep -q 'wallcheck'"
check "it tried every way it knows"        "[ \"\$(grep -c 'POSIX file' '$SCRIPTED')\" -ge 2 ]"
printf '%s\n' "$WAS" > "$STATE/wallpaper"

OUT=$(NIMO_OSA_FAIL=1 wall set)
check "unreadable is a different sentence" "printf '%s' \"\$OUT\" | grep -q 'cannot read your wallpaper\|could not read the wallpaper'"
check "and it names the permission"        "printf '%s' \"\$OUT\" | grep -q 'Automation'"

# ---- flipping through them ----------------------------------------------
#
# A list of names tells you nothing about a wallpaper. Stepping applies each
# one as you move, so the thing you are choosing is on your own screen — and
# `q` puts back the one you started with, which means two different things
# have to be remembered: what you had before nimo ever touched it, and what it
# is showing you right now.

rm -rf "$BOX/.nimo/backups"
: > "$SCRIPTED"

step() {
    PATH="$FAKE:$PATH" HOME="$BOX" bash -c '
        NIMO_VERSION=test; NIMO_QUIET=1; NIMO_COLOR=never
        NIMO_DRY_RUN=0; NIMO_RESTORE=0
        for m in ui core pick scan clean setup desktop dock wall undo tools; do
            . "'"$ROOT"'/lib/$m.sh"
        done
        nimo_init_colors
        nimo_wall_dirs() { printf "%s\n" "'"$PICS"'" "'"$PICS"'/Solid Colors"; }
        case "$1" in
            next) nimo_cmd_next ;;
            prev) nimo_cmd_prev ;;
        esac' _ "$1" 2>&1
}

check "next says where in the list it is"  "step next | grep -q ' of 3'"
check "and it asks the system to set it"   "grep -q 'set picture to' '$SCRIPTED'"
check "it remembers where it got to"       "[ -s '$BOX/.nimo/backups/wallpaper-at.txt' ]"
check "and it kept what you had before"    "grep -q 'Sonoma Horizon' '$BOX/.nimo/backups/wallpaper.txt'"

FIRST=$(step next); SECOND=$(step next)
check "two steps land somewhere else"      "[ \"\$FIRST\" != \"\$SECOND\" ]"
check "prev comes back to the first"       "[ \"\$(step prev | grep ' of 3')\" = \"\$(printf '%s' \"\$FIRST\" | grep ' of 3')\" ]"
check "stepping past the end wraps round"  "step next >/dev/null; step next >/dev/null; step next >/dev/null; step next | grep -q ' of 3'"

check "the before is not overwritten"      "grep -q 'Sonoma Horizon' '$BOX/.nimo/backups/wallpaper.txt'"

# and the browser itself: n moves, q puts back, enter keeps
# a literal newline in a variable: $(printf '\n') is stripped by the command
# substitution, and "enter" is exactly the key these two checks are about
ENTER=$'\n'

browse() {
    printf '%s' "$1" | NIMO_PICK_FORCE=1 PATH="$FAKE:$PATH" HOME="$BOX" bash -c '
        NIMO_VERSION=test; NIMO_QUIET=1; NIMO_COLOR=never
        NIMO_DRY_RUN=0; NIMO_RESTORE=0; NIMO_LIST=0
        NIMO_RANDOM=0; NIMO_ASSUME_YES=0; NIMO_LIMIT=15
        for m in ui core pick scan clean setup desktop dock wall undo tools; do
            . "'"$ROOT"'/lib/$m.sh"
        done
        nimo_init_colors
        nimo_wall_dirs() { printf "%s\n" "'"$PICS"'" "'"$PICS"'/Solid Colors"; }
        nimo_cmd_wallpaper' _ 2>&1
}

check "the browser draws a position"       "browse 'q' | grep -q 'of 3'"
check "and says the keys out loud"         "browse 'q' | grep -q 'enter  keep it'"
check "and that it changes as you move"    "browse 'q' | grep -q 'on your screen as you move'"
check "q says it put the old one back"     "browse 'q' | grep -q 'put back the one you had'"
check "enter keeps what is showing"        "browse \"n\$ENTER\" | grep -q 'Kept'"
check "and points at the way back"         "browse \"n\$ENTER\" | grep -q 'wallpaper --restore'"
check "moving applies each one on the way" ": > '$SCRIPTED'; browse \"nn\$ENTER\" >/dev/null; [ \"\$(grep -c 'set picture to' '$SCRIPTED')\" -ge 3 ]"

check "--restore arms it again"            "wall restore >/dev/null 2>&1; [ ! -f '$BOX/.nimo/backups/wallpaper.txt' ]"
check "and forgets where it had got to"    "[ ! -f '$BOX/.nimo/backups/wallpaper-at.txt' ]"

# ---- the menu, on the platform that has everything -----------------------
#
# The other half of the Windows check: the rows nimo drops there have to still
# be here, or "only offer what this computer can do" quietly becomes "offer
# less than it can".

mmenu() { printf '\n' | PATH="$FAKE:$PATH" HOME="$BOX" bash "$MIN" clear --no-color 2>&1; }

check "the mac menu offers the dock"      "mmenu | grep -q 'Dock'"
check "and the trash"                     "mmenu | grep -q 'Trash'"
check "and everything at once"            "mmenu | grep -q 'Everything'"
check "seven rows, numbered"              "[ \"\$(mmenu | grep -c '^ *[0-9]  ')\" = 7 ]"
check "and the prompt agrees there are 7" "mmenu | grep -q 'Which one? 1-7'"

# and the "/" list, on the platform that has all of it
mslash() { printf '/\n/quit\n' | NIMO_REPL_FORCE=1 NIMO_NO_CLEAR=1 PATH="$FAKE:$PATH" HOME="$BOX" bash "$MIN" -q --no-color 2>&1; }

mmenu_arrows() { printf 'q' | NIMO_PICK_FORCE=1 PATH="$FAKE:$PATH" HOME="$BOX" bash "$MIN" --menu --no-color 2>&1; }
check "the arrow menu offers the dock"    "mmenu_arrows | grep -q 'dock'"
check "and the wallpaper and the setup"   "mmenu_arrows | grep -q 'wallpaper' && mmenu_arrows | grep -q 'setup'"
check "tidy calls it a mac"               "PATH=\"$FAKE:\$PATH\" HOME=\"$BOX\" bash \"$MIN\" tidy --dry-run -q --no-color </dev/null 2>&1 | grep -q 'minimal mac'"

check "the mac list offers the dock"      "mslash | grep -q '/fastdock'"
check "and the menu bar and the apps"     "mslash | grep -q '/hide' && mslash | grep -q '/apps'"
check "and the finder setup, not windows" "mslash | grep -q 'finder, dock and keyboard'"

# ---- what starts when you sign in ----------------------------------------
#
# System Events knows the login items; the LaunchAgents in your own Library
# are files, and nimo only reports those. Nothing here is uninstalled: a
# program you stop still starts when you open it yourself.

printf 'Dropbox\t/Applications/Dropbox.app\nSpotify\t/Applications/Spotify.app\n' > "$STATE/login-items"
mkdir -p "$BOX/Library/LaunchAgents"
: > "$BOX/Library/LaunchAgents/com.example.updater.plist"

check "it reads your login items"         "mac startup --list -q --no-color | grep -q 'Dropbox'"
check "and the agents in your Library"    "mac startup --list -q --no-color | grep -q 'com.example.updater'"
check "an agent is listed as one"         "mac startup --list -q --no-color | grep -q 'background agent'"
check "and it is yours to turn off"       "! mac startup --list -q --no-color | grep -q 'only reports these'"
check "it counts all of them"             "mac startup --list -q --no-color | grep -q '3 things'"
check "it promises to delete nothing"     "mac startup --list -q --no-color | grep -q 'uninstalled or deleted'"
check "a list changes nothing"            "grep -q Dropbox '$STATE/login-items'"

mstop() { printf '%s\n' "$1" | PATH="$FAKE:$PATH" HOME="$BOX" bash "$MIN" startup -y -q --no-color 2>&1; }

check "stopping one removes it"           "mstop '1' >/dev/null 2>&1; ! grep -q Dropbox '$STATE/login-items'"
check "and leaves the other alone"        "grep -q Spotify '$STATE/login-items'"
check "the agent file is still there"     "[ -f '$BOX/Library/LaunchAgents/com.example.updater.plist' ]"
check "--undo makes the login item again" "mac startup --undo -q --no-color >/dev/null 2>&1; grep -q Dropbox '$STATE/login-items'"
check "with the path it had before"       "grep -q '/Applications/Dropbox.app' '$STATE/login-items'"
check "and it shows up in min undo"       "mac undo --list -q --no-color | grep -q 'stopped things starting'"

# A LaunchAgent in your own Library is yours. It is unloaded first and then
# moved: a plist still loaded and no longer on disk is the one state worth
# avoiding. Nothing is deleted — the file is in ~/.nimo/backups.
check "stopping an agent moves the plist" "mstop '3' >/dev/null 2>&1; [ ! -f '$BOX/Library/LaunchAgents/com.example.updater.plist' ]"
check "it is moved, not deleted"          "ls '$BOX/.nimo/backups/startup'/*.plist >/dev/null 2>&1"
check "launchctl was asked to unload it"  "grep -q 'unload' '$STATE/launchctl'"
check "--undo puts the plist back"        "mac startup --undo -q --no-color >/dev/null 2>&1; [ -f '$BOX/Library/LaunchAgents/com.example.updater.plist' ]"
check "and loads it again"                "grep -q 'load -w' '$STATE/launchctl'"

# ---- all of it at once ---------------------------------------------------

: > "$WROTE"
printf '\n\n' | PATH="$FAKE:$PATH" HOME="$BOX" NIMO_PICK_FORCE=1 \
    bash "$MIN" tidy -y -q --no-color >/dev/null 2>&1
check "min tidy runs the whole way through" "[ \$? -eq 0 ]"
check "min tidy applied the preferences"    "[ -s '$WROTE' ]"
check "min tidy left the dock alone"        "[ \$(grep -c . '$DOCK') -eq 5 ]"

# ---- verdict -------------------------------------------------------------

printf '\n'
if [ "$FAIL" -eq 0 ]; then
    printf '  %s✓ %d passed%s\n\n' "$G" "$PASS" "$Z"
    exit 0
else
    printf '  %s%d passed, %d failed%s%s\n\n' "$R" "$PASS" "$FAIL" "$FAILED" "$Z"
    exit 1
fi
