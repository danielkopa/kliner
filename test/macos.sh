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

BOX=$(mktemp -d "${TMPDIR:-/tmp}/nimo-macos.XXXXXX") || exit 1
trap 'rm -rf "$BOX"' EXIT INT TERM

FAKE="$BOX/fakebin"
STATE="$BOX/state"
mkdir -p "$FAKE" "$STATE"

DOCK="$STATE/dock"                 # one app url per line
WROTE="$STATE/defaults-writes"     # every plain `defaults write`
SCRIPTED="$STATE/osascript"        # every osascript that ran
SQL="$STATE/sqlite"                # the last resort wallpaper path
: > "$WROTE"; : > "$SCRIPTED"; : > "$SQL"

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

# A `defaults` that is real enough for nimo, and only for nimo.
cat > "$FAKE/defaults" <<SHIM
#!/bin/sh
DOCK="$DOCK"
WROTE="$WROTE"
SHIM
cat >> "$FAKE/defaults" <<'SHIM'
verb="${1:-}"; shift 2>/dev/null || true

case "$verb" in
    read)
        domain="${1:-}"; key="${2:-}"
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
NIMO_FAKE_CURRENT_WALL="$BOX/pics/Sonoma Horizon.heic"
SHIM
cat >> "$FAKE/osascript" <<'SHIM'
shift 2>/dev/null || true
printf '%s\n' "$*" >> "$SCRIPTED"
case "$*" in
    *"get desktop picture"*)
        [ "${NIMO_OSA_FAIL:-0}" = "1" ] && exit 1
        echo "$NIMO_FAKE_CURRENT_WALL"
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

mac() { PATH="$FAKE:$PATH" HOME="$BOX" bash "$MIN" "$@"; }

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
