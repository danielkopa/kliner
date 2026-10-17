#!/usr/bin/env bash
# nimo :: lib/startup.sh — what launches when you sign in.
#
# The slowest, most cluttered part of a computer is usually the part nobody
# looks at: the six things that start themselves every morning. nimo lists
# them, lets you tick the ones to stop, and writes down every removal so
# `min undo` can put them back.
#
# Nothing is uninstalled and nothing is deleted. Stopping a thing from
# starting itself is a shortcut moved aside or a registry value written down
# and removed — the program is still there, and still starts when you open it.

NIMO_STARTUP_STORE=""

nimo_startup_store() {
    printf '%s' "$NIMO_BACKUP_DIR/startup"
}

# One line per thing that starts itself:
#
#   where <TAB> name <TAB> what it runs
#
# where:  run       a registry value under HKCU, yours to change
#         machine   the same under HKLM, which needs an administrator
#         folder    a shortcut in the Startup folder
#         login     a macOS login item
#         agent     a LaunchAgent plist in your own Library
nimo_startup_list() {
    case "$(nimo_platform)" in
        windows) nimo_startup_list_windows ;;
        macos)   nimo_startup_list_macos ;;
    esac
}

nimo_startup_list_windows() {
    local name cmd item

    while IFS=$'\t' read -r name cmd; do
        [ -n "${name:-}" ] || continue
        printf 'run\t%s\t%s\n' "$name" "${cmd:-}"
    done <<INNER
$(nimo_win_run_values "$NIMO_WIN_RUN")
INNER

    while IFS=$'\t' read -r name cmd; do
        [ -n "${name:-}" ] || continue
        printf 'machine\t%s\t%s\n' "$name" "${cmd:-}"
    done <<INNER
$(nimo_win_run_values "$NIMO_WIN_RUN_MACHINE")
INNER

    local folder
    folder=$(nimo_win_startup_folder)
    [ -d "$folder" ] || return 0
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        name=$(basename "$item")
        case "$name" in .*|desktop.ini) continue ;; esac
        printf 'folder\t%s\t%s\n' "${name%.*}" "$item"
    done <<INNER
$(find "$folder" -mindepth 1 -maxdepth 1 -type f 2>/dev/null)
INNER
}

# System Events knows the login items; the LaunchAgents in your own Library
# are files, and nimo only reports those.
nimo_startup_list_macos() {
    local names paths i=1 name path item

    names=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null) || names=""
    paths=$(osascript -e 'tell application "System Events" to get the path of every login item' 2>/dev/null) || paths=""

    if [ -n "$names" ]; then
        # AppleScript answers "a, b, c" on one line
        while [ -n "$names" ]; do
            name="${names%%, *}"
            if [ "$name" = "$names" ]; then names=""; else names="${names#*, }"; fi
            path="${paths%%, *}"
            if [ "$path" = "$paths" ]; then paths=""; else paths="${paths#*, }"; fi
            [ -n "$name" ] || continue
            printf 'login\t%s\t%s\n' "$name" "${path:-}"
            i=$((i + 1))
        done
    fi

    [ -d "$HOME/Library/LaunchAgents" ] || return 0
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        name=$(basename "$item")
        printf 'agent\t%s\t%s\n' "${name%.plist}" "$item"
    done <<INNER
$(find "$HOME/Library/LaunchAgents" -mindepth 1 -maxdepth 1 -name '*.plist' 2>/dev/null)
INNER
}

nimo_startup_where() {
    case "$1" in
        run)     printf 'starts itself' ;;
        machine) printf 'set for everyone' ;;
        folder)  printf 'startup folder' ;;
        login)   printf 'login item' ;;
        agent)   printf 'background agent' ;;
        *)       printf '' ;;
    esac
}

# And why nimo will not touch it.
nimo_startup_why() {
    case "$1" in
        machine) printf 'needs an administrator' ;;
        *)       printf 'not nimos to change' ;;
    esac
}

# Can nimo turn this one off without asking anybody for a password?
#
# Everything in your own home folder, and nothing outside it. A LaunchAgent in
# ~/Library/LaunchAgents is yours; the same file in /Library belongs to the
# machine and nimo never sees it, because it never looks there.
nimo_startup_mine() {
    case "$1" in
        run|folder|login|agent) return 0 ;;
        *) return 1 ;;
    esac
}

# Stop one thing from starting itself. Every branch writes down enough to
# put it back before it changes anything.
nimo_startup_stop() {
    local where="$1" name="$2" what="$3" dest

    case "$where" in
        run)
            nimo_win_record "$NIMO_WIN_RUN" "$name"
            nimo_reg_erase "$NIMO_WIN_RUN" "$name"
            return $? ;;
        folder)
            mkdir -p "$(nimo_startup_store)" 2>/dev/null
            dest=$(nimo_free_name "$(nimo_startup_store)" "$(basename "$what")")
            printf 'file\t%s\t%s\n' "$what" "$dest" >> "$NIMO_STARTUP_STORE"
            mv "$what" "$dest" 2>/dev/null \
                || { nimo_undo_drop_last "$NIMO_STARTUP_STORE"; return 1; }
            return 0 ;;
        login)
            printf 'login\t%s\t%s\n' "$name" "$what" >> "$NIMO_STARTUP_STORE"
            osascript -e "tell application \"System Events\" to delete login item \"$name\"" >/dev/null 2>&1 \
                || { nimo_undo_drop_last "$NIMO_STARTUP_STORE"; return 1; }
            return 0 ;;
        agent)
            # Unload it first, so it stops now rather than at the next login,
            # and then move the file. A plist that is still loaded and no
            # longer on disk is the one state worth avoiding.
            [ -f "$what" ] || return 1
            launchctl unload -w "$what" >/dev/null 2>&1
            mkdir -p "$(nimo_startup_store)" 2>/dev/null
            dest=$(nimo_free_name "$(nimo_startup_store)" "$(basename "$what")")
            printf 'agent\t%s\t%s\n' "$what" "$dest" >> "$NIMO_STARTUP_STORE"
            mv "$what" "$dest" 2>/dev/null \
                || { nimo_undo_drop_last "$NIMO_STARTUP_STORE"; return 1; }
            return 0 ;;
    esac
    return 1
}

# Replay one startup log: shortcuts move back, login items are made again,
# and the registry values this same run wrote down come back with them.
# shellcheck disable=SC2120  # min undo hands over an exact log; --undo does not
nimo_startup_undo() {
    # $2 and $3 let `min dock --restore` on Windows share this replay without
    # telling you its pins are about to start themselves.
    local log="${1:-}" title="${2:-start these again}" verb="${3:-will start again}"
    local kind a b back=0 missed=0 prefs="" was

    [ "${NIMO_UNDO_QUIET:-0}" = "1" ] || nimo_header
    nimo_panel_open "$title"

    [ -n "$log" ] || log=$(nimo_newest "$NIMO_UNDO_DIR"/startup-*.tsv) || log=""
    if [ -z "$log" ] || [ ! -f "$log" ]; then
        nimo_dim "nimo has not stopped anything from starting yet"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    while IFS=$'\t' read -r kind a b; do
        [ -n "${kind:-}" ] || continue
        case "$kind" in
            file)
                if [ -e "$b" ] && [ ! -e "$a" ]; then
                    mv "$b" "$a" 2>/dev/null && back=$((back + 1))
                else
                    missed=$((missed + 1))
                fi ;;
            agent)
                if [ -e "$b" ] && [ ! -e "$a" ]; then
                    if mv "$b" "$a" 2>/dev/null; then
                        launchctl load -w "$a" >/dev/null 2>&1
                        back=$((back + 1))
                    else
                        missed=$((missed + 1))
                    fi
                else
                    missed=$((missed + 1))
                fi ;;
            login)
                if osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$b\", hidden:false}" >/dev/null 2>&1; then
                    back=$((back + 1))
                else
                    missed=$((missed + 1))
                fi ;;
            prefs)
                prefs="$a" ;;
        esac
    done < "$log"

    # and the registry values this same run wrote down.
    #
    # nimo_setup_restore opens a panel of its own, and closing a panel puts
    # NIMO_PAD back to the outer two spaces — so the line printed after this
    # sat at the wrong indent, inside a panel that was still open. Panels do
    # not nest; this one is held open by hand.
    if [ -n "$prefs" ] && [ -f "$prefs" ]; then
        was="$NIMO_PAD"
        NIMO_UNDO_QUIET=1
        nimo_setup_restore "$prefs" >/dev/null 2>&1
        NIMO_UNDO_QUIET=0
        NIMO_PAD="$was"
        back=$((back + $(nimo_file_lines "$prefs")))
    fi

    nimo_ok "$(nimo_plural "$back" thing) $verb"
    [ "$missed" -gt 0 ] && nimo_dim "$missed had already been changed, so nimo left them alone"
    nimo_panel_close
    nimo_blank
    return 0
}

# Stop one named thing, for a caller that already knows which. The name is
# matched whole and without regard to case, because a name typed by a person
# and a name read out of a plist are rarely spelled the same way.
nimo_startup_stop_one() {
    local targets="$1" line where name what found=""

    while IFS=$'\t' read -r where name what; do
        [ -n "${where:-}" ] || continue
        if nimo_same_word "$name" "$NIMO_ONLY"; then
            found="$where	$name	$what"
            break
        fi
    done <<INNER
$targets
INNER

    if [ -z "$found" ]; then
        nimo_warn "nimo cannot stop \"$NIMO_ONLY\", it is not one of the ones it can change"
        nimo_blank
        return 1
    fi

    if ! nimo_confirm "Stop $name from starting?"; then
        nimo_blank
        nimo_dim "left as it was"
        nimo_blank
        return 0
    fi

    mkdir -p "$NIMO_UNDO_DIR" "$NIMO_BACKUP_DIR" 2>/dev/null
    NIMO_STARTUP_STORE=$(nimo_free_file "$NIMO_UNDO_DIR/startup-$(date +%Y%m%d-%H%M%S)" .tsv)
    : > "$NIMO_STARTUP_STORE"
    nimo_look_log
    printf 'prefs\t%s\t\n' "$NIMO_SETUP_LOG" >> "$NIMO_STARTUP_STORE"

    where="${found%%	*}"
    name=$(printf '%s' "$found" | cut -f2)
    what=$(printf '%s' "$found" | cut -f3-)

    nimo_blank
    if nimo_startup_stop "$where" "$name" "$what"; then
        nimo_ok "$name will not start itself again"
        nimo_blank
        nimo_dim "changed your mind?  min startup --undo"
    else
        nimo_warn "$name could not be changed and was left alone"
    fi
    nimo_blank
    return 0
}

# Two names are the same word if they differ only by case or by edge spaces.
nimo_same_word() {
    local a="$1" b="$2"
    a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"
    b="${b#"${b%%[![:space:]]*}"}"; b="${b%"${b##*[![:space:]]}"}"
    shopt -s nocasematch 2>/dev/null
    case "$a" in
        "$b") shopt -u nocasematch 2>/dev/null; return 0 ;;
    esac
    shopt -u nocasematch 2>/dev/null
    return 1
}

nimo_cmd_startup() {
    if [ "${NIMO_UNDO:-0}" = "1" ] || [ "${NIMO_RESTORE:-0}" = "1" ]; then
        nimo_startup_undo
        return 0
    fi

    nimo_header

    case "$(nimo_platform)" in
        macos|windows) ;;
        *)
            nimo_warn "nimo knows how to read this on macOS and Windows, not here"
            nimo_blank
            return 0 ;;
    esac

    nimo_progress "looking at what starts itself …"
    local list count
    list=$(nimo_startup_list)
    count=$(nimo_line_count "$list")
    nimo_progress_done

    nimo_panel_open "what starts when you sign in"

    if [ "$count" -eq 0 ]; then
        nimo_ok "Nothing starts itself. That is rare, and good."
        nimo_panel_close
        nimo_blank
        return 0
    fi

    # Two lists: the ones nimo can turn off, and the ones it will only report.
    # Both are named. A count of things you cannot see is not a report.
    local labels="" targets="" others="" theirs=0 mine=0 where name what
    while IFS=$'\t' read -r where name what; do
        [ -n "${where:-}" ] || continue
        if nimo_startup_mine "$where"; then
            mine=$((mine + 1))
            labels="$labels$(printf '%-28s  %s' "$name" "$(nimo_startup_where "$where")")
"
            targets="${targets}${where}	${name}	${what}
"
        else
            theirs=$((theirs + 1))
            others="$others$(printf '%-28s  %s' "$name" "$(nimo_startup_why "$where")")
"
        fi
    done <<INNER
$list
INNER

    # No numbers here. The panel is the report; the numbers belong to the
    # picker, and printing both meant reading the same list twice.
    local label
    while IFS= read -r label; do
        [ -n "$label" ] || continue
        nimo_say "$label"
    done <<INNER
$labels
INNER

    if [ "$theirs" -gt 0 ]; then
        [ "$mine" -gt 0 ] && nimo_blank
        nimo_dim "nimo only reports these:"
        nimo_blank
        while IFS= read -r label; do
            [ -n "$label" ] || continue
            nimo_say "$label"
        done <<INNER
$others
INNER
    fi

    nimo_blank
    nimo_rule
    nimo_total "Starts itself" "$(nimo_plural "$((mine + theirs))" thing)"
    nimo_panel_close

    nimo_blank
    nimo_dim "nothing here is uninstalled or deleted, a program you stop still"
    nimo_dim "starts when you open it yourself"
    nimo_blank

    if [ "$mine" -eq 0 ]; then
        nimo_dim "none of these are yours to change"
        nimo_blank
        return 0
    fi

    # --only names one of them outright, so something without a terminal — the
    # app, a script — can stop exactly one thing without a picker. It still
    # will not act without a yes.
    if [ -n "${NIMO_ONLY:-}" ]; then
        nimo_startup_stop_one "$targets"
        return $?
    fi

    if [ "${NIMO_LIST:-0}" = "1" ] || [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "run  min startup  to pick what stops"
        nimo_blank
        return 0
    fi

    local wanted
    if ! wanted=$(nimo_pick multi "↑↓ move   space tick   a all   n none   enter confirm   q cancel" "$labels"); then
        nimo_dim "nothing was changed"
        nimo_blank
        return 0
    fi
    if [ -z "$wanted" ]; then
        nimo_dim "nothing ticked, nothing was changed"
        nimo_blank
        return 0
    fi

    local n
    n=$(printf '%s' "$wanted" | wc -w | tr -d ' ')
    if ! nimo_confirm "Stop $(nimo_plural "$n" thing) from starting?"; then
        nimo_blank
        nimo_dim "left as it was"
        nimo_blank
        return 0
    fi

    mkdir -p "$NIMO_UNDO_DIR" "$NIMO_BACKUP_DIR" 2>/dev/null
    NIMO_STARTUP_STORE=$(nimo_free_file "$NIMO_UNDO_DIR/startup-$(date +%Y%m%d-%H%M%S)" .tsv)
    : > "$NIMO_STARTUP_STORE"
    nimo_look_log
    # A registry value goes back through the preferences log, a shortcut goes
    # back through this one. Naming that log here is what keeps it one undo
    # instead of two commands the user has to know to run in order.
    printf 'prefs\t%s\t\n' "$NIMO_SETUP_LOG" >> "$NIMO_STARTUP_STORE"

    local stopped=0 failed=0 line
    for i in $wanted; do
        line=$(printf '%s' "$targets" | sed -n "${i}p")
        [ -n "$line" ] || continue
        where="${line%%	*}"
        name=$(printf '%s' "$line" | cut -f2)
        what=$(printf '%s' "$line" | cut -f3-)
        if nimo_startup_stop "$where" "$name" "$what"; then
            stopped=$((stopped + 1))
        else
            failed=$((failed + 1))
        fi
    done

    nimo_blank
    if [ "$stopped" = "1" ]; then
        nimo_ok "1 thing will not start itself again"
    else
        nimo_ok "$stopped things will not start themselves again"
    fi
    [ "$failed" -gt 0 ] && nimo_warn "$failed could not be changed and were left alone"
    nimo_blank
    nimo_dim "changed your mind?  min startup --undo"
    nimo_blank
    return 0
}
