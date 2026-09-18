#!/usr/bin/env bash
# nimo :: lib/tools.sh — min top, min doctor, min update.

# ---- min top -------------------------------------------------------------

# ---- min top -------------------------------------------------------------
#
# "Where did my disk go" is a question about a tree, and a flat list of your
# home folder answers it once and then leaves you to guess. So this one steps:
# pick the folder that is too big and look inside it, and keep going until you
# find the thing.
#
# It measures and nothing else. There is no key in here that deletes anything.

# kb <TAB> path, biggest first, for the children of one folder
# -a, because a folder of files is a folder you can step into and see nothing
# without it: du lists directories only unless you ask for everything.
nimo_top_children() {
    du -k -a -d 1 "$1" 2>/dev/null \
        | awk -v h="$1" -F'\t' '$2 != h && $2 != h"/"' \
        | sort -rn
}

nimo_top_draw() {
    local where="$1" limit="$2" list max total shown=0 kb path name
    list=$(nimo_top_children "$where" | head -n "$limit")
    total=$(nimo_path_kb "$where")

    if [ "$where" = "$HOME" ]; then
        nimo_panel_open "biggest folders in your home"
    else
        nimo_panel_open "inside ${where#$HOME/}"
    fi

    if [ -z "$list" ]; then
        nimo_dim "nothing in here worth measuring"
        nimo_blank
        nimo_rule
        nimo_total "All of it" "$(nimo_human_kb "$total")"
        nimo_panel_close
        return 1
    fi

    max=$(printf '%s\n' "$list" | head -1 | awk '{print $1 + 0}')
    while IFS=$'\t' read -r kb path; do
        [ -n "${path:-}" ] || continue
        name="${path##*/}"
        [ -d "$path" ] && name="$name/"
        printf "%s%-${NIMO_TOP_NAME_WIDTH}s %s%10s%s  %s\n" \
            "$NIMO_PAD" "$name" \
            "$(nimo_size_color "$kb")" "$(nimo_human_kb "$kb")" "$NIMO_C_RESET" \
            "$(nimo_meter "$kb" "$max" "$NIMO_BAR_WIDTH")"
        shown=$((shown + 1))
    done <<EOF
$list
EOF

    nimo_blank
    nimo_rule
    if [ "$where" != "$HOME" ]; then
        nimo_total "All of it" "$(nimo_human_kb "$total")"
    elif [ "${NIMO_COLS:-80}" -lt 52 ]; then
        # the long label is longer than the whole label column in a narrow
        # window, and a total that sticks out of the table is not a total
        nimo_total "Your home" "$(nimo_human_kb "$total")"
    else
        nimo_total "Everything in your home" "$(nimo_human_kb "$total")"
    fi
    nimo_panel_close
    return 0
}

# The labels the picker offers: the folders you can step into, and the way up.
nimo_top_choices() {
    local where="$1" limit="$2" kb path
    [ "$where" = "$HOME" ] || printf '..\t%s\n' "$(dirname "$where")"
    while IFS=$'\t' read -r kb path; do
        [ -n "${path:-}" ] || continue
        [ -d "$path" ] || continue
        printf '%s\t%s\n' "${path##*/}" "$path"
    done <<EOF
$(nimo_top_children "$where" | head -n "$limit")
EOF
}

nimo_cmd_top() {
    local limit="${NIMO_LIMIT:-15}" where="$HOME"

    # a folder to start in, if you named one:  min top Downloads
    if [ -n "${NIMO_TARGET:-}" ]; then
        if [ -d "$HOME/$NIMO_TARGET" ]; then
            where="$HOME/$NIMO_TARGET"
        elif [ -d "$NIMO_TARGET" ]; then
            where=$(cd -P "$NIMO_TARGET" && pwd)
        fi
    fi

    # Stepping through the list is already held to your home folder. Naming a
    # folder on the command line was not, so `min top /etc` measured /etc and
    # listed what was in it before the first step pulled it back.
    if ! nimo_inside_home "$where"; then
        nimo_err "nimo only looks inside your home folder"
        nimo_blank
        return 1
    fi

    nimo_header

    while :; do
        nimo_progress "measuring ${where#$HOME/} …"
        local drew
        nimo_top_draw "$where" "$limit"; drew=$?
        nimo_progress_done

        # One question, and only one: is there anybody here to answer it?
        if ! nimo_pick_capable || [ "${NIMO_LIST:-0}" = "1" ]; then
            nimo_blank
            nimo_dim "this is only a measurement, nothing here is deleted or changed"
            if [ "$drew" = "0" ]; then
                nimo_dim "in a terminal you can step into these:  min top"
            fi
            nimo_dim "to see what is actually safe to remove:  min preview"
            nimo_blank
            return 0
        fi

        local choices labels line name path choice
        choices=$(nimo_top_choices "$where" "$limit")
        labels=$(printf '%s\n' "$choices" | cut -f1)

        if [ -z "$(printf '%s' "$labels" | tr -d '[:space:]')" ]; then
            nimo_blank
            nimo_dim "nothing in here to step into"
            nimo_blank
            return 0
        fi

        nimo_blank
        if ! choice=$(nimo_pick single "↑↓ move   enter look inside   q stop" "$labels") \
           || [ -z "$choice" ]; then
            nimo_blank
            nimo_dim "nothing was changed, min top only ever measures"
            nimo_blank
            return 0
        fi

        line=$(printf '%s\n' "$choices" | sed -n "${choice}p")
        path=$(printf '%s' "$line" | cut -f2)
        [ -n "$path" ] || return 0

        # Up as far as your home folder and no further. The guard that keeps
        # nimo out of the rest of the disk keeps it out of here too, even
        # though nothing in this command can change anything.
        case "$path" in
            "$HOME") where="$HOME" ;;
            "$HOME"/*) where="$path" ;;
            *) where="$HOME" ;;
        esac
    done
}

# ---- min doctor ----------------------------------------------------------

nimo_os_line() {
    if nimo_is_macos && nimo_have sw_vers; then
        printf '%s %s (%s)' \
            "$(sw_vers -productName 2>/dev/null)" \
            "$(sw_vers -productVersion 2>/dev/null)" \
            "$(uname -m)"
        return 0
    fi

    # Git Bash answers `uname -s` with MINGW64_NT-10.0-22631, which is true and
    # unreadable. The number on the end is the Windows build, and 22000 is
    # where 11 begins; the prefix says which of the three bashes this is.
    if [ "$(nimo_platform)" = "windows" ]; then
        local raw build name shell
        raw=$(uname -s 2>/dev/null)
        build=$(printf '%s' "$raw" | sed -n 's/.*[-.]\([0-9][0-9]*\)$/\1/p')
        name="Windows"
        if [ -n "$build" ] && [ "$build" -ge 22000 ] 2>/dev/null; then
            name="Windows 11"
        elif [ -n "$build" ]; then
            name="Windows 10"
        fi
        case "$raw" in
            MINGW*)  shell="Git Bash" ;;
            MSYS*)   shell="MSYS2" ;;
            CYGWIN*) shell="Cygwin" ;;
            *)       shell="" ;;
        esac
        if [ -n "$shell" ]; then
            printf '%s (%s · %s)' "$name" "$shell" "$(uname -m)"
        else
            printf '%s (%s)' "$name" "$(uname -m)"
        fi
        return 0
    fi

    printf '%s %s (%s)' "$(uname -s)" "$(uname -r)" "$(uname -m)"
}

nimo_uptime_line() {
    local raw
    raw=$(uptime 2>/dev/null) || { printf 'unknown'; return 0; }
    printf '%s' "$raw" | sed -e 's/.*up[ ]*//' -e 's/,[ ]*[0-9]* user.*//' -e 's/[ ]*$//'
}

nimo_memory_line() {
    local kb=0
    if nimo_is_macos && nimo_have sysctl; then
        kb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 ))
    elif [ -r /proc/meminfo ]; then
        kb=$(awk '/^MemTotal:/ {print $2 + 0; exit}' /proc/meminfo 2>/dev/null)
    elif [ "$(nimo_platform)" = "windows" ]; then
        # Git Bash usually mounts /proc, but MSYS2 without it and Cygwin do
        # not always, and then doctor simply had no memory line at all.
        kb=$(( $(nimo_win_number '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory') / 1024 ))
    fi
    [ "${kb:-0}" -gt 0 ] || return 1
    nimo_human_kb "$kb"
}

nimo_battery_line() {
    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_win_battery
        return $?
    fi
    nimo_have pmset || return 1
    local raw pct state
    raw=$(pmset -g batt 2>/dev/null) || return 1
    case "$raw" in
        *InternalBattery*) ;;
        *) return 1 ;;
    esac
    pct=$(printf '%s' "$raw" | sed -n 's/.*[^0-9]\([0-9]\{1,3\}\)%.*/\1/p' | head -1)
    [ -n "$pct" ] || return 1
    # "discharging" contains "charging", so the loose glob that used to live
    # here called an emptying battery "plugged in". Decide from the line pmset
    # prints about where the power is coming from, then refine on the exact
    # "; charging" / "; charged" tokens.
    state="on battery"
    case "$raw" in
        *"'AC Power'"*|*"AC attached"*) state="plugged in" ;;
    esac
    case "$raw" in
        *"; charged"*)     state="charged" ;;
        *"; charging"*)    state="charging" ;;
        *"; discharging"*) state="on battery" ;;
    esac
    printf '%s%%  ·  %s' "$pct" "$state"
}

nimo_cmd_doctor() {
    nimo_header
    nimo_panel_open "your computer"

    nimo_fact "System" "$(nimo_os_line)"
    nimo_fact "Uptime" "$(nimo_uptime_line)"

    local free total used
    free=$(nimo_disk_free_kb); free=${free:-0}
    total=$(nimo_disk_total_kb); total=${total:-0}
    used=$((total - free))
    if [ "$total" -gt 0 ]; then
        # "9.0 GB free of 9.7 GB" plus a bar is the widest thing doctor says.
        # In a narrow window the second number goes: how much is left is the
        # question, and how big the disk is was never the answer.
        if [ "${NIMO_COLS:-80}" -lt 44 ]; then
            nimo_fact "Disk" "$(nimo_human_kb "$free") free" \
                "$(nimo_bar "$used" "$total" "$NIMO_BAR_WIDTH")"
        else
            nimo_fact "Disk" \
                "$(printf '%s free of %s' "$(nimo_human_kb "$free")" "$(nimo_human_kb "$total")")" \
                "$(nimo_bar "$used" "$total" "$NIMO_BAR_WIDTH")"
        fi
    fi

    local mem battery
    mem=$(nimo_memory_line) && nimo_fact "Memory" "$mem"
    battery=$(nimo_battery_line) && nimo_fact "Battery" "$battery"

    nimo_blank
    nimo_fact "Desktop" "$(nimo_plural "$(nimo_count_dir_items "$(nimo_desktop_dir)")" item)"
    nimo_fact "Downloads" "$(nimo_plural "$(nimo_count_dir_items "$(nimo_downloads_dir)")" item)"

    # How much of that has just been sitting there. A count on its own says
    # how full a folder is; the same count with "and most of it a month old"
    # beside it says whether that is a problem. Both are shallow finds and
    # cost nothing.
    local nimo_desk_old nimo_down_old
    nimo_desk_old=$(nimo_older_count "$(nimo_desktop_dir)" 30)
    nimo_down_old=$(nimo_older_count "$(nimo_downloads_dir)" 30)
    [ "${nimo_desk_old:-0}" -gt 0 ] \
        && nimo_fact "Desktop older" "$nimo_desk_old over 30 days"
    [ "${nimo_down_old:-0}" -gt 0 ] \
        && nimo_fact "Downloads older" "$nimo_down_old over 30 days"

    # Twelve numbers the window draws as a strip. Printed only for the window:
    # a row of commas is no use to somebody reading this in a terminal.
    [ "${NIMO_FROM_APP:-0}" = "1" ] \
        && nimo_fact "Months" "$(nimo_month_counts)"
    # One source for what is in the bin, whatever this system calls it.
    if nimo_has_trash; then
        if [ "$(nimo_platform)" = "windows" ]; then
            nimo_fact "Recycle Bin" "$(nimo_plural "$(nimo_trash_count)" item)"
        else
            nimo_fact "Trash" "$(nimo_plural "$(nimo_trash_count)" item)"
        fi
    fi

    # The newest thing nimo has done, so the one question anybody has —
    # "what has this actually changed?" — is answered where they are looking
    # rather than on another page.
    local last
    last=$(nimo_undo_last 2>/dev/null) && [ -n "$last" ] \
        && nimo_fact "Last change" "$last"

    # Everything above is a handful of reads and is instant. Everything below
    # walks the caches, which on a full disk is tens of seconds. With --fast
    # doctor stops here, so something that wants a face on the screen now can
    # ask twice: once for this, and again for the rest.
    if [ "${NIMO_FAST:-0}" = "1" ]; then
        nimo_blank
        nimo_fact "nimo" "v$NIMO_VERSION" "$(command -v min 2>/dev/null || true)"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    nimo_blank
    nimo_progress "adding up what could be freed …"
    nimo_register_targets
    nimo_scan
    local i safe_kb=0
    i=0
    while [ "$i" -lt "$NIMO_T_N" ]; do
        [ "${NIMO_T_SAFETY[$i]}" = "safe" ] && safe_kb=$((safe_kb + ${NIMO_R_KB[$i]}))
        i=$((i + 1))
    done
    nimo_progress_done

    if [ "$safe_kb" -gt 0 ]; then
        nimo_fact "Junk" "$(nimo_human_kb "$safe_kb")" "→ min clean"
    else
        nimo_fact "Junk" "none worth mentioning"
    fi

    nimo_blank
    # the most useful thing doctor can say is what to do about it
    local n_desk n_down suggestion=""
    n_desk=$(nimo_count_children "$(nimo_desktop_dir)")
    n_down=$(nimo_count_children "$(nimo_downloads_dir)")
    if [ "${n_desk:-0}" -ge 20 ]; then
        suggestion="min clear desktop"
    elif [ "${n_down:-0}" -ge 50 ]; then
        suggestion="min clear downloads"
    elif [ "$safe_kb" -gt 2097152 ]; then
        suggestion="min clean"
    fi
    [ -n "$suggestion" ] && nimo_fact "Next" "$suggestion"

    local where
    where=$(command -v min 2>/dev/null || true)
    if [ -n "$where" ]; then
        nimo_fact "nimo" "v$NIMO_VERSION" "$where"
    else
        nimo_fact "nimo" "v$NIMO_VERSION" "not on your PATH, run ./install.sh"
    fi
    nimo_panel_close
    nimo_blank
}

# ---- min update ----------------------------------------------------------

nimo_cmd_update() {
    nimo_header
    nimo_panel_open "update"

    # nimo does not reach the network. That is one of the six rules, and a
    # command that quietly ran `git pull` for you was the one place it was not
    # true — which made the rule worth exactly nothing.
    #
    # So this says what to type. Fetching a new copy of a tool that rearranges
    # your files is a thing to do with your eyes open, and it is one line.
    if [ ! -d "$NIMO_ROOT/.git" ]; then
        nimo_warn "this copy of nimo is not a git repository"
        nimo_dim "$NIMO_ROOT"
        nimo_panel_close
        nimo_blank
        return 1
    fi

    nimo_fact "nimo" "v$NIMO_VERSION" "$NIMO_ROOT"
    nimo_blank
    nimo_dim "nimo never reaches the network by itself, so it does not update itself."
    nimo_dim "one line, and you can see what it does:"
    nimo_blank
    printf '%s%s    cd %s && git pull%s\n' \
        "$NIMO_PAD" "$NIMO_C_BOLD" "$NIMO_ROOT" "$NIMO_C_RESET"
    nimo_blank
    nimo_panel_close
    nimo_blank
    return 0
}

# ---- min tidy ------------------------------------------------------------
#
# The whole point of nimo, in one command: a desktop with nothing on it,
# a dock with only what you open, a calm wallpaper, sane preferences.
# Every step asks first. Every step can be undone.

nimo_cmd_tidy() {
    local plat what
    plat=$(nimo_platform)
    case "$plat" in
        macos)   what="mac" ;;
        windows) what="pc" ;;
        *)       what="computer" ;;
    esac

    nimo_logo
    nimo_blank
    nimo_dim "a few steps toward a minimal $what. each one asks before it does"
    nimo_dim "anything, and each one can be undone."
    nimo_blank

    local was_quiet="${NIMO_QUIET:-0}"
    NIMO_QUIET=1

    nimo_cmd_desktop
    nimo_cmd_downloads
    nimo_cmd_screenshots
    # Running every step and letting the ones this machine cannot do print an
    # apology turned tidy into a list of things nimo would not be doing.
    case "$plat" in
        macos|windows)
            nimo_cmd_dock
            nimo_cmd_wallpaper
            nimo_cmd_setup
            nimo_cmd_startup ;;
    esac

    NIMO_QUIET="$was_quiet"

    nimo_panel_open "done"
    nimo_ok "That is a minimal $what."
    nimo_blank
    nimo_dim "undo the desktop     min desktop --undo"
    nimo_dim "undo the downloads   min downloads --undo"
    case "$plat" in
        macos)
            nimo_dim "undo the dock        min dock --restore" ;;
        windows)
            nimo_dim "undo the taskbar     min dock --restore" ;;
    esac
    case "$plat" in
        macos|windows)
            nimo_dim "undo the wallpaper   min wallpaper --restore"
            nimo_dim "undo the settings    min setup --restore"
            nimo_dim "start things again   min startup --undo" ;;
    esac
    nimo_blank
    nimo_dim "and when the disk fills up again   min clean"
    nimo_panel_close
    nimo_blank
    return 0
}

# ---- the menu ------------------------------------------------------------
#
# `min` on its own, in a real terminal, is a way in rather than a wall of
# help text. Anywhere else it prints the help, exactly as before.

nimo_menu_items() {
    local plat
    plat=$(nimo_platform)
    printf '%s\n' \
        "$(printf '%-10s %s' tidy      'the whole thing, step by step')" \
        "$(printf '%-10s %s' desktop   'clear your desktop, nothing lost')" \
        "$(printf '%-10s %s' downloads 'the same, for your downloads')"
    case "$plat" in
        macos)   printf '%s\n' "$(printf '%-10s %s' dock 'keep only the apps you open')" ;;
        windows) printf '%s\n' "$(printf '%-10s %s' dock 'keep only the apps you pin')" ;;
    esac
    case "$plat" in
        macos|windows)
            printf '%s\n' \
                "$(printf '%-10s %s' wallpaper 'a calmer wallpaper')" \
                "$(printf '%-10s %s' setup     'a small, sane setup for this computer')" ;;
    esac
    printf '%s\n' \
        "$(printf '%-10s %s' preview   'what could be freed, changing nothing')" \
        "$(printf '%-10s %s' clean     'free it up, after asking')" \
        "$(printf '%-10s %s' top       'the biggest folders in your home')" \
        "$(printf '%-10s %s' doctor    'how your computer is doing')" \
        "$(printf '%-10s %s' undo      'put something back')" \
        "$(printf '%-10s %s' help      'everything there is')"
}

# prints the chosen command name, or nothing at all
nimo_menu() {
    local labels choice
    labels=$(nimo_menu_items)
    choice=$(nimo_pick single "↑↓ move   enter choose   q cancel" "$labels") || return 1
    [ -n "$choice" ] || return 1
    printf '%s\n' "$labels" | sed -n "${choice}p" | awk '{print $1}'
    return 0
}

# ---- min clear -----------------------------------------------------------
#
# One word for the thing nimo is actually for. Type /clear and pick what
# should be clear; or say it outright with /clear desktop.

nimo_cmd_clear() {
    local target="${NIMO_TARGET:-}"

    if [ -z "$target" ]; then
        nimo_header
        nimo_panel_open "what should be clear?"

        # counting is cheap here, and choosing is much easier when the menu
        # already tells you where the mess actually is
        nimo_progress "counting …"
        local n_desk n_down n_shots n_trash kb_desk kb_down kb_trash has_trash
        local desk down
        desk=$(nimo_desktop_dir)
        down=$(nimo_downloads_dir)
        n_desk=$(nimo_count_sortable "$desk")
        n_down=$(nimo_count_sortable "$down")
        n_shots=$(nimo_count_loose_screenshots)
        n_trash=0
        kb_trash=0
        has_trash=0
        if nimo_has_trash; then
            has_trash=1
            n_trash=$(nimo_trash_count)
            kb_trash=$(nimo_trash_kb)
        fi
        kb_desk=$(nimo_children_kb "$desk")
        kb_down=$(nimo_children_kb "$down")
        nimo_progress_done

        # a bar apiece, drawn against whichever pile is biggest, so the menu
        # shows you where the mess actually is before you have chosen anything
        local most=1 total_kb
        for n in "$n_desk" "$n_down" "$n_shots" "$n_trash"; do
            [ "${n:-0}" -gt "$most" ] && most="$n"
        done
        total_kb=$((kb_desk + kb_down + kb_trash))

        # It said "everything here can be undone" with the trash sitting in the
        # list, which is the one row that cannot be. Say which.
        if [ "$has_trash" = "1" ]; then
            nimo_dim "all of it can be undone, except taking the rubbish out"
        else
            nimo_dim "everything here can be undone"
        fi
        [ "$total_kb" -gt 0 ] && nimo_dim "$(nimo_human_kb "$total_kb") in all, and none of it is deleted"
        nimo_blank

        # The rows are built, not written out. A fixed list of seven meant
        # Windows was offered a Dock it does not have and a Recycle Bin nimo
        # is not allowed to empty — and picking either got you an apology.
        # Nothing is offered here that this computer cannot actually do.
        local labels="" targets="" choice
        nimo_offer() {
            labels="${labels}$1
"
            targets="${targets}$2
"
        }

        # a mark apiece, drawn from the box-drawing block every terminal has,
        # rather than an icon set fetched from somewhere with a licence
        nimo_offer "$(printf '%s %-11s %-11s %s' ▤ Desktop     "$(nimo_plural "$n_desk" item)"  "$(nimo_bar "$n_desk" "$most" "$NIMO_MENU_BAR_WIDTH")")" desktop
        nimo_offer "$(printf '%s %-11s %-11s %s' ▼ Downloads   "$(nimo_plural "$n_down" item)"  "$(nimo_bar "$n_down" "$most" "$NIMO_MENU_BAR_WIDTH")")" downloads
        nimo_offer "$(printf '%s %-11s %-11s %s' ▣ Screenshots "$n_shots loose" "$(nimo_bar "$n_shots" "$most" "$NIMO_MENU_BAR_WIDTH")")" screenshots
        if [ "$has_trash" = "1" ]; then
            local bin_label="Trash"
            [ "$(nimo_platform)" = "windows" ] && bin_label="Bin"
            nimo_offer "$(printf '%s %-11s %-11s %s' ○ "$bin_label" "$(nimo_plural "$n_trash" item)"  "$(nimo_bar "$n_trash" "$most" "$NIMO_MENU_BAR_WIDTH")")" trash
        fi
        case "$(nimo_platform)" in
            macos)
                nimo_offer "$(printf '%s %-11s %s' ■ Dock        'the apps you never open')" dock ;;
            windows)
                nimo_offer "$(printf '%s %-11s %s' ■ Taskbar     'the apps you never open')" dock ;;
        esac
        nimo_offer "$(printf '%s %-11s %s' ◍ Disk        'caches your apps rebuild by themselves')" disk
        nimo_offer "$(printf '%s %-11s %s' ◆ Everything  'all of it, one step at a time')" everything

        if ! choice=$(nimo_pick single "↑↓ move   enter choose   q cancel" "$labels") || [ -z "$choice" ]; then
            nimo_panel_close
            nimo_blank
            nimo_dim "nothing was changed"
            nimo_blank
            return 0
        fi
        nimo_panel_close

        target=$(printf '%s\n' "$targets" | sed -n "${choice}p")
        [ -n "$target" ] || {
            nimo_blank
            nimo_dim "nothing was changed"
            nimo_blank
            return 0
        }
    fi

    case "$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')" in
        desktop|files)        nimo_cmd_desktop ;;
        downloads|download)   nimo_cmd_downloads ;;
        screenshots|shots)    nimo_cmd_screenshots ;;
        dock|apps)            nimo_cmd_dock ;;
        trash|bin)            nimo_cmd_empty ;;
        disk|cache|caches|junk|space) nimo_cmd_clean ;;
        everything|all)       nimo_cmd_tidy ;;
        *)
            nimo_header
            nimo_warn "nimo cannot clear \"$target\""
            nimo_dim "try  /clear  on its own and pick from the list"
            nimo_blank
            return 1 ;;
    esac
    return 0
}
