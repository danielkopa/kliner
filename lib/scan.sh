#!/usr/bin/env bash
# nimo :: lib/scan.sh — what nimo knows how to look at.
#
# Every target has:
#   id      short name, usable with --only
#   label   what the user sees
#   kind    contents | tree | older | findname | bigfiles
#   safety  safe   -> nimo may delete it after you confirm
#           review -> nimo only reports it, never deletes it
#   note    one-line explanation
#   spec    one or more paths (newline separated)

NIMO_T_ID=(); NIMO_T_LABEL=(); NIMO_T_KIND=()
NIMO_T_SAFETY=(); NIMO_T_NOTE=(); NIMO_T_SPEC=()
NIMO_T_N=0

nimo_register() {
    local id="$1" label="$2" kind="$3" safety="$4" note="$5"
    shift 5
    local spec="" p
    for p in "$@"; do spec="${spec}${p}
"; done
    NIMO_T_ID[$NIMO_T_N]="$id"
    NIMO_T_LABEL[$NIMO_T_N]="$label"
    NIMO_T_KIND[$NIMO_T_N]="$kind"
    NIMO_T_SAFETY[$NIMO_T_N]="$safety"
    NIMO_T_NOTE[$NIMO_T_N]="$note"
    NIMO_T_SPEC[$NIMO_T_N]="$spec"
    NIMO_T_N=$((NIMO_T_N + 1))
}

nimo_register_targets_macos() {
    nimo_register user-caches "App caches" contents safe \
        "your apps rebuild them" \
        "$HOME/Library/Caches"

    nimo_register logs "Application logs" contents safe \
        "old log files" \
        "$HOME/Library/Logs"

    nimo_register crash-reports "Crash reports" contents safe \
        "reports nobody reads" \
        "$HOME/Library/Logs/DiagnosticReports"

    nimo_register trash "Trash" contents safe \
        "already thrown away" \
        "$HOME/.Trash"

    nimo_register quicklook "QuickLook thumbnails" contents safe \
        "regenerated on demand" \
        "$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache"

    nimo_register mail-downloads "Mail attachments cache" contents safe \
        "copies of opened attachments" \
        "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"

    nimo_register xcode "Xcode derived data" contents safe \
        "rebuilt on your next build" \
        "$HOME/Library/Developer/Xcode/DerivedData" \
        "$HOME/Library/Developer/CoreSimulator/Caches"

    nimo_register homebrew "Homebrew cache" contents safe \
        "downloaded bottles" \
        "$HOME/Library/Caches/Homebrew"

    nimo_register node "npm / yarn / pnpm cache" contents safe \
        "download caches" \
        "$HOME/.npm/_cacache" \
        "$HOME/Library/Caches/Yarn" \
        "$HOME/.cache/yarn" \
        "$HOME/Library/pnpm/store"

    nimo_register python "pip cache" contents safe \
        "downloaded wheels" \
        "$HOME/Library/Caches/pip" \
        "$HOME/.cache/pip"

    # ---- review only: nimo shows these, you decide ----

    nimo_register downloads "Old downloads" older review \
        "untouched for a while" \
        "$HOME/Downloads"

    nimo_register ios-backups "iPhone / iPad backups" tree review \
        "losing these loses backups" \
        "$HOME/Library/Application Support/MobileSync/Backup"

    nimo_register xcode-archives "Xcode archives" tree review \
        "your shipped builds" \
        "$HOME/Library/Developer/Xcode/Archives"

    nimo_register device-support "Xcode device support" tree review \
        "re-downloaded on connect" \
        "$HOME/Library/Developer/Xcode/iOS DeviceSupport"

    nimo_register node-modules "node_modules folders" findname review \
        "npm install brings them back" \
        "$HOME"

    nimo_register big-files "Files over 500 MB" bigfiles review \
        "the heavyweights" \
        "$HOME"
}

nimo_register_targets_linux() {
    nimo_register user-caches "User cache" contents safe \
        "rebuilt automatically" \
        "$HOME/.cache"

    nimo_register trash "Trash" contents safe \
        "already thrown away" \
        "$HOME/.local/share/Trash/files" \
        "$HOME/.local/share/Trash/info"

    nimo_register node "npm / yarn cache" contents safe \
        "download caches" \
        "$HOME/.npm/_cacache" \
        "$HOME/.cache/yarn"

    nimo_register python "pip cache" contents safe \
        "downloaded wheels" \
        "$HOME/.cache/pip"

    nimo_register downloads "Old downloads" older review \
        "untouched for a while" \
        "$HOME/Downloads"

    nimo_register node-modules "node_modules folders" findname review \
        "npm install brings them back" \
        "$HOME"

    nimo_register big-files "Files over 500 MB" bigfiles review \
        "the heavyweights" \
        "$HOME"
}

nimo_register_targets_windows() {
    nimo_register temp "Temp files" contents safe \
        "windows rebuilds these" \
        "$HOME/AppData/Local/Temp"

    nimo_register crash-reports "Crash dumps" contents safe \
        "reports nobody reads" \
        "$HOME/AppData/Local/CrashDumps"

    nimo_register node "npm / yarn cache" contents safe \
        "download caches" \
        "$HOME/AppData/Roaming/npm-cache/_cacache" \
        "$HOME/AppData/Local/Yarn/Cache"

    nimo_register python "pip cache" contents safe \
        "downloaded wheels" \
        "$HOME/AppData/Local/pip/Cache"

    nimo_register browser-cache "Browser caches" contents safe \
        "rebuilt as you browse" \
        "$HOME/AppData/Local/Google/Chrome/User Data/Default/Cache" \
        "$HOME/AppData/Local/Google/Chrome/User Data/Default/Code Cache" \
        "$HOME/AppData/Local/Microsoft/Edge/User Data/Default/Cache" \
        "$HOME/AppData/Local/Microsoft/Edge/User Data/Default/Code Cache" \
        "$HOME/AppData/Local/BraveSoftware/Brave-Browser/User Data/Default/Cache" \
        "$HOME/AppData/Local/Mozilla/Firefox/Profiles" \
        "$HOME/AppData/Local/Opera Software/Opera Stable/Cache"

    # Every one of these is a folder its own tool refills on demand. None of
    # them is a setting, a login, or anything you typed.
    nimo_register dev-caches "Build caches" contents safe \
        "your tools rebuild them" \
        "$HOME/.gradle/caches" \
        "$HOME/.cargo/registry/cache" \
        "$HOME/AppData/Local/NuGet/Cache" \
        "$HOME/AppData/Local/go-build"

    # Deliberately not here, and this is the reason rather than an oversight:
    #
    #   AppData/Local/Package Cache          the installers Windows keeps so
    #   AppData/Local/Microsoft/VisualStudio/Packages   Repair and Uninstall
    #                                        still work. They look exactly
    #                                        like junk and are not.
    #   .nuget/packages                      restorable, but only with the
    #                                        network, and only if the feed is
    #                                        still up.

    nimo_register app-caches "App caches" contents safe \
        "the apps refill them" \
        "$HOME/AppData/Roaming/Microsoft/Teams/Cache" \
        "$HOME/AppData/Roaming/Slack/Cache" \
        "$HOME/AppData/Roaming/Code/Cache" \
        "$HOME/AppData/Roaming/Code/CachedData" \
        "$HOME/AppData/Roaming/discord/Cache" \
        "$HOME/AppData/Roaming/Spotify/Data"

    nimo_register thumbnails "Thumbnail cache" contents safe \
        "explorer draws them again" \
        "$HOME/AppData/Local/Microsoft/Windows/Explorer"

    nimo_register downloads "Old downloads" older review \
        "untouched for a while" \
        "$(nimo_downloads_dir)"

    nimo_register node-modules "node_modules folders" findname review \
        "npm install brings them back" \
        "$HOME"

    nimo_register big-files "Files over 500 MB" bigfiles review \
        "the heavyweights" \
        "$HOME"
}

nimo_register_targets() {
    NIMO_T_ID=(); NIMO_T_LABEL=(); NIMO_T_KIND=()
    NIMO_T_SAFETY=(); NIMO_T_NOTE=(); NIMO_T_SPEC=()
    NIMO_T_N=0
    case "$(nimo_platform)" in
        macos)   nimo_register_targets_macos ;;
        windows) nimo_register_targets_windows ;;
        *)       nimo_register_targets_linux ;;
    esac
}

nimo_target_paths() {
    printf '%s' "${NIMO_T_SPEC[$1]}"
}

# Size of everything inside a directory, not counting the directory itself.
nimo_children_kb() {
    [ -d "$1" ] || { printf '0'; return 0; }
    find "$1" -mindepth 1 -maxdepth 1 -exec du -sk {} + 2>/dev/null \
        | awk '{t += $1} END {printf "%d", t + 0}'
}

# Sum of registered, selected target paths that live strictly inside $1.
# Without this, ~/Library/Caches would be counted once on its own and once
# again through Homebrew, pip and friends that live inside it.
nimo_nested_kb() {
    local parent="$1" total=0 i=0 q
    while [ "$i" -lt "$NIMO_T_N" ]; do
        if nimo_selected "$i"; then
            while IFS= read -r q; do
                [ -n "$q" ] || continue
                case "$q" in
                    "$parent"/*)
                        [ -e "$q" ] && total=$((total + $(nimo_path_kb "$q")))
                        ;;
                esac
            done <<EOF
$(nimo_target_paths "$i")
EOF
        fi
        i=$((i + 1))
    done
    printf '%s' "$total"
}

# True when a path sits inside something nimo already counts as safe junk,
# so a 2 GB cache file is not also reported as a heavyweight.
nimo_under_safe() {
    local f="$1" i=0 q
    while [ "$i" -lt "$NIMO_T_N" ]; do
        if [ "${NIMO_T_SAFETY[$i]}" = "safe" ]; then
            while IFS= read -r q; do
                [ -n "$q" ] || continue
                case "$f" in
                    "$q"/*) return 0 ;;
                esac
            done <<EOF
$(nimo_target_paths "$i")
EOF
        fi
        i=$((i + 1))
    done
    return 1
}

# measure target $1 -> prints "<kb> <count>"
nimo_measure() {
    local i="$1" kind="${NIMO_T_KIND[$1]}"
    local kb=0 count=0 p sub

    case "$kind" in
        contents)
            local nested
            while IFS= read -r p; do
                [ -n "$p" ] || continue
                [ -d "$p" ] || continue
                sub=$(nimo_children_kb "$p")
                nested=$(nimo_nested_kb "$p")
                sub=$((sub - nested))
                [ "$sub" -lt 0 ] && sub=0
                kb=$((kb + sub))
                count=$((count + $(nimo_count_children "$p")))
            done <<EOF
$(nimo_target_paths "$i")
EOF
            ;;
        tree)
            while IFS= read -r p; do
                [ -n "$p" ] || continue
                [ -e "$p" ] || continue
                sub=$(nimo_path_kb "$p")
                kb=$((kb + sub))
                count=$((count + $(nimo_count_children "$p")))
            done <<EOF
$(nimo_target_paths "$i")
EOF
            ;;
        older)
            local days="${NIMO_DAYS:-30}"
            while IFS= read -r p; do
                [ -n "$p" ] || continue
                [ -d "$p" ] || continue
                count=$((count + $(find "$p" -mindepth 1 -maxdepth 1 -mtime "+$days" 2>/dev/null | wc -l | tr -d ' ')))
                sub=$(find "$p" -mindepth 1 -maxdepth 1 -mtime "+$days" -exec du -sk {} + 2>/dev/null | awk '{t += $1} END {printf "%d", t + 0}')
                kb=$((kb + sub))
            done <<EOF
$(nimo_target_paths "$i")
EOF
            ;;
        findname)
            local hit
            while IFS= read -r p; do
                [ -n "$p" ] || continue
                [ -d "$p" ] || continue
                while IFS= read -r hit; do
                    [ -n "$hit" ] || continue
                    nimo_under_safe "$hit" && continue
                    count=$((count + 1))
                    kb=$((kb + $(nimo_path_kb "$hit")))
                done <<EOF
$(find "$p" -maxdepth 5 -type d -name node_modules -prune 2>/dev/null)
EOF
            done <<EOF
$(nimo_target_paths "$i")
EOF
            ;;
        bigfiles)
            local hit
            while IFS= read -r p; do
                [ -n "$p" ] || continue
                [ -d "$p" ] || continue
                while IFS= read -r hit; do
                    [ -n "$hit" ] || continue
                    nimo_under_safe "$hit" && continue
                    count=$((count + 1))
                    kb=$((kb + $(nimo_path_kb "$hit")))
                done <<EOF
$(find "$p" -maxdepth 6 -type f -size +500000k 2>/dev/null)
EOF
            done <<EOF
$(nimo_target_paths "$i")
EOF
            ;;
    esac

    printf '%s %s' "$kb" "$count"
}

# Fills NIMO_R_KB / NIMO_R_COUNT for every registered target.
#
# Measuring is almost entirely waiting on the disk, so the targets are
# measured a handful at a time instead of one after another. On a Mac with a
# large ~/Library/Caches and an Xcode folder this is the difference between
# a scan you wait for and a scan you do not.
nimo_scan() {
    NIMO_R_KB=(); NIMO_R_COUNT=()
    local n="$NIMO_T_N"
    [ "$n" -gt 0 ] || return 0

    local dir=""
    dir=$(mktemp -d "${TMPDIR:-/tmp}/nimo-scan.XXXXXX" 2>/dev/null) || dir=""

    if [ -z "$dir" ]; then
        nimo_scan_serial
        return 0
    fi

    nimo_progress "looking in $n places …"

    local i=0 running=0 batch="${NIMO_JOBS:-6}"
    while [ "$i" -lt "$n" ]; do
        nimo_measure "$i" > "$dir/$i" 2>/dev/null &
        running=$((running + 1))
        if [ "$running" -ge "$batch" ]; then
            wait
            running=0
        fi
        i=$((i + 1))
    done
    wait
    nimo_progress_done

    local result
    i=0
    while [ "$i" -lt "$n" ]; do
        result=$(cat "$dir/$i" 2>/dev/null)
        case "$result" in
            *' '*) ;;
            *) result="0 0" ;;
        esac
        NIMO_R_KB[$i]="${result%% *}"
        NIMO_R_COUNT[$i]="${result##* }"
        i=$((i + 1))
    done

    rm -rf "$dir" 2>/dev/null
    return 0
}

# The same thing, one at a time, for when mktemp is not available.
nimo_scan_serial() {
    NIMO_R_KB=(); NIMO_R_COUNT=()
    local i=0 result
    while [ "$i" -lt "$NIMO_T_N" ]; do
        nimo_progress "looking in  ${NIMO_T_LABEL[$i]} …"
        result=$(nimo_measure "$i")
        NIMO_R_KB[$i]="${result%% *}"
        NIMO_R_COUNT[$i]="${result##* }"
        i=$((i + 1))
    done
    nimo_progress_done
}

# is target $1 selected by --only?
nimo_selected() {
    [ -z "${NIMO_ONLY:-}" ] && return 0
    case ",${NIMO_ONLY}," in
        *",${NIMO_T_ID[$1]},"*) return 0 ;;
        *) return 1 ;;
    esac
}
