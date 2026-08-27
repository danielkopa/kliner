#!/usr/bin/env bash
# nimo :: lib/repl.sh — a prompt you can talk to.
#
#   nimo › /clean desktop
#   nimo › /wallpaper
#   nimo › /undo
#
# The slash is optional. So is remembering the exact word: "clear desktop",
# "tidy desktop" and "/desktop" all mean the same thing. Anything that starts
# with a dash is passed straight through as a flag.

# Every command, with the words that reach it.
#
# Grouped by what you came here to do, not by what nimo happens to call them,
# and only the ones this computer can actually carry out — a Windows machine
# was being offered a dock and a menu bar it does not have.
#
# The two counts are one `find` apiece. They are the reason the list is worth
# opening rather than remembering: it says where the mess is before you have
# chosen anything.

# The description is the part a narrow window drops. The list is still a list
# of what you can type without it, and a wrapped one is not.
nimo_repl_row() {
    if [ "${NIMO_COLS:-80}" -lt 62 ]; then
        printf '%s%s %s\n' "$NIMO_PAD" "$1" "$2"
        return 0
    fi
    printf '%s%s %-14s %s%s%s\n' \
        "$NIMO_PAD" "$1" "$2" "$NIMO_C_DIM" "$3" "$NIMO_C_RESET"
}

nimo_repl_head() {
    printf '%s%s%s%s\n\n' "$NIMO_PAD" "$NIMO_C_BOLD" "$1" "$NIMO_C_RESET"
}

nimo_repl_list() {
    local plat n_desk n_down n_shots also
    plat=$(nimo_platform)

    n_desk=$(nimo_count_sortable "$(nimo_desktop_dir)")
    n_down=$(nimo_count_sortable "$(nimo_downloads_dir)")
    n_shots=$(nimo_count_loose_screenshots)

    nimo_panel_open "what you can type"

    nimo_repl_head "clear something"
    nimo_repl_row ▤ /clear       "desktop, downloads, screenshots — you pick"
    if [ "$n_desk" -gt 0 ]; then
        nimo_repl_row ▼ /desktop "$(nimo_plural "$n_desk" item) on your desktop right now"
    else
        nimo_repl_row ▼ /desktop "your desktop is already clear"
    fi
    if [ "$n_down" -gt 0 ]; then
        nimo_repl_row ▽ /downloads "$(nimo_plural "$n_down" item) in your downloads"
    else
        nimo_repl_row ▽ /downloads "nothing loose in your downloads"
    fi
    if [ "$n_shots" -gt 0 ]; then
        nimo_repl_row ▣ /screenshots "$(nimo_plural "$n_shots" "loose screenshot"), into one folder"
    else
        nimo_repl_row ▣ /screenshots "no screenshots lying about"
    fi
    nimo_blank

    nimo_repl_head "make it yours"
    nimo_repl_row ◐ /wallpaper   "flip through them, live, on your own screen"
    nimo_repl_row → /next        "the next one — /prev goes back"
    nimo_repl_row ◑ /dark        "switch appearance — /light switches back"
    nimo_repl_row ◇ /zen         "stop drawing icons on the desktop at all"
    if [ "$plat" = "windows" ]; then
        nimo_repl_row ■ /setup   "explorer and the taskbar, tuned once"
    else
        nimo_repl_row ■ /setup   "finder, dock and keyboard, tuned once"
        nimo_repl_row ▸ /fastdock "no wait before the dock slides"
    fi
    nimo_blank

    nimo_repl_row ⏻ /startup     "what launches when you sign in"
    nimo_blank

    nimo_repl_head "get the disk back"
    nimo_repl_row ◍ /clean       "caches your apps rebuild by themselves"
    nimo_repl_row ◆ /top         "the biggest things — step inside them"
    nimo_repl_row ⧉ /duplicates  "the same file, kept more than once"
    nimo_repl_row ▢ /cleandoc    "empty a file, keeping what was in it"
    nimo_blank

    nimo_repl_head "and back again"
    nimo_repl_row ↺ /undo        "anything nimo has done, one line at a time"
    if [ "$NIMO_AUTO" = "1" ]; then
        nimo_repl_row ● /auto    "on — /auto off puts the questions back"
    else
        nimo_repl_row ○ /auto    "stop asking me — one yes for the session"
    fi
    nimo_blank

    case "$plat" in
        macos)   also="/tidy /doctor /preview /empty /dock /hide /apps /menu /quit" ;;
        windows) also="/tidy /doctor /preview /empty /dock /hide /apps /menu /quit" ;;
        *)       also="/tidy /doctor /preview /empty /menu /quit" ;;
    esac
    printf '%s%s%-14s %s%s\n' "$NIMO_PAD" "$NIMO_C_DIM" "also" "$also" "$NIMO_C_RESET"
    printf '%s%s%-14s %s%s\n' "$NIMO_PAD" "$NIMO_C_DIM" "sort with" "--by letter   or   --by date" "$NIMO_C_RESET"

    nimo_panel_close
    nimo_blank
    nimo_dim "or say it outright:  /clear desktop"
    nimo_blank
}

# A phrase in, a command name out. Empty when nimo has no idea.
#
# Everything is matched twice: as typed, and with the spaces taken out, so
# "/clear desktop" and "/cleardesktop" are the same command and nobody has to
# remember which one nimo wanted.
nimo_repl_command() {
    local squashed
    squashed=$(printf '%s' "$1" | tr -d ' ')

    case "$squashed" in
        clear|whattoclear|clearsomething)
            printf 'clear'; return 0 ;;
        cleardesktop|cleandesktop|tidydesktop|fixdesktop|sortdesktop|clearfiles|cleanfiles|sortfiles|tidyfiles)
            printf 'desktop'; return 0 ;;
        cleardownloads|cleandownloads|tidydownloads|sortdownloads|downloads)
            printf 'downloads'; return 0 ;;
        cleardock|cleandock|tidydock|fixdock|clearapps|cleanapps)
            printf 'dock'; return 0 ;;
        screenshots|screenshot|clearscreenshots|gatherscreenshots|shots)
            printf 'screenshots'; return 0 ;;
        zen|hideicons|hidedesktop|quietdesktop|focus)
            printf 'zen'; return 0 ;;
        dark|darkmode|godark)
            printf 'dark'; return 0 ;;
        light|lightmode|golight)
            printf 'light'; return 0 ;;
        hide|hidemenubar|menubar|hidemenu)
            printf 'hide'; return 0 ;;
        duplicates|dupes|copies|samefile|findduplicates)
            printf 'duplicates'; return 0 ;;
        apps|unusedapps|oldapps|whatdoiuse)
            printf 'apps'; return 0 ;;
        cleandoc|cleanfile|blankfile|emptyfile|blank)
            printf 'blank'; return 0 ;;
        startup|startupitems|loginitems|whatstarts|autostart|startsitself)
            printf 'startup'; return 0 ;;
        next|nextwallpaper|nextwall|anotherone)
            printf 'next'; return 0 ;;
        prev|previous|prevwallpaper|lastone|oneback)
            printf 'prev'; return 0 ;;
        fastdock|dockfast|quickdock|speeddock)
            printf 'dock --fast'; return 0 ;;
        empty|emptytrash|takeouttrash|bin)
            printf 'empty'; return 0 ;;
        cleardisk|cleandisk|freespace|clearspace|cleancache|clearcache|clearjunk|cleanjunk)
            printf 'clean'; return 0 ;;
        cleartrash|cleantrash)
            printf 'empty'; return 0 ;;
    esac

    case "$1" in
        clear|"clear what"|"what should be clear")
            printf 'clear' ;;
        tidy|all|everything|"do it"|"do everything"|minimal|"make it minimal")
            printf 'tidy' ;;
        desktop|"clean desktop"|"clear desktop"|"tidy desktop"|"fix desktop"|"sort desktop"|files|"clear files"|"sort files")
            printf 'desktop' ;;
        downloads|"clean downloads"|"clear downloads"|"tidy downloads"|"sort downloads")
            printf 'downloads' ;;
        screenshots|screenshot|shots|"gather screenshots"|"clear screenshots")
            printf 'screenshots' ;;
        zen|focus|"hide icons"|"hide desktop"|"quiet desktop"|calm)
            printf 'zen' ;;
        dark|"dark mode"|"go dark")
            printf 'dark' ;;
        light|"light mode"|"go light")
            printf 'light' ;;
        hide|"hide menu bar"|"menu bar")
            printf 'hide' ;;
        duplicates|dupes|copies|"same file"|"find duplicates")
            printf 'duplicates' ;;
        apps|"unused apps"|"old apps")
            printf 'apps' ;;
        blank|"clean doc"|"clean file"|"empty file"|"blank file")
            printf 'blank' ;;
        startup|"login items"|"startup items"|"what starts"|autostart)
            printf 'startup' ;;
        next|"next wallpaper"|"another one")
            printf 'next' ;;
        prev|previous|"previous wallpaper"|"the last one"|"one back")
            printf 'prev' ;;
        "fast dock"|"dock fast"|"speed up the dock")
            printf 'dock --fast' ;;
        empty|"empty trash"|trash|bin)
            printf 'empty' ;;
        dock|"clean dock"|"clear dock"|"tidy dock"|"fix dock")
            printf 'dock' ;;
        wallpaper|wall|background|"change wallpaper"|"set wallpaper"|desktop-picture)
            printf 'wallpaper' ;;
        preview|scan|look|check|"what can i free"|dry-run)
            printf 'preview' ;;
        clean|"clean disk"|"clean up"|"free space"|junk|cache|caches|space|disk)
            printf 'clean' ;;
        top|big|biggest|"big files"|large|size|sizes)
            printf 'top' ;;
        doctor|status|health|info|about|how)
            printf 'doctor' ;;
        setup|prefs|preferences|defaults|settings)
            printf 'setup' ;;
        undo|back|revert|restore|oops|"put it back")
            printf 'undo' ;;
        update|upgrade|pull)
            printf 'update' ;;
        menu)
            printf 'menu' ;;
        version)
            printf 'version' ;;
        *)
            printf '' ;;
    esac
}

# How many characters two words start with in common.
nimo_shared_prefix() {
    local a="$1" b="$2" n=0
    while [ -n "$a" ] && [ -n "$b" ]; do
        [ "${a%"${a#?}"}" = "${b%"${b#?}"}" ] || break
        a="${a#?}"
        b="${b#?}"
        n=$((n + 1))
    done
    printf '%s' "$n"
}

# When the words miss, say what was probably meant.
#
# Substring matching is no help here: "wallpapr" neither contains nor is
# contained by "wallpaper". Shared prefix is what actually catches a typo,
# and every word in the line gets a turn, so "clean deskopt" finds desktop.
nimo_repl_guess() {
    local phrase="$1" word name shared best="" best_score=0

    for word in $phrase; do
        for name in clear auto tidy desktop downloads screenshots dock wallpaper zen dark light hide empty apps duplicates preview clean top doctor setup undo update menu; do
            shared=$(nimo_shared_prefix "$word" "$name")
            if [ "$shared" -gt "$best_score" ]; then
                best_score="$shared"
                best="$name"
            fi
        done
    done

    if [ "$best_score" -ge 3 ]; then
        printf '%s' "$best"
        return 0
    fi

    printf ''
    return 1
}

# ---- saying yes once, for the whole session ------------------------------
#
# Every command asks before it changes anything, which is right the first few
# times and wearing by the twentieth. This is the same bargain a terminal
# agent offers: you say yes once, deliberately, knowing what it covers, and
# then nothing asks again until you leave.

# NIMO_AUTO=1 in the environment starts the prompt already in auto, for the
# times you know exactly what you are about to do:  NIMO_AUTO=1 min
NIMO_AUTO="${NIMO_AUTO:-0}"
case "$NIMO_AUTO" in
    1|true|yes) NIMO_AUTO=1 ;;
    *)          NIMO_AUTO=0 ;;
esac

nimo_auto_explain() {
    nimo_panel_open "yes to everything"
    nimo_say "nimo stops asking. Every command runs the moment you type it."
    nimo_blank
    nimo_dim "this covers this session only — it is off again next time"
    nimo_dim "undo still works for everything that has one:  /undo"
    nimo_dim "the trash is the exception. /empty has no undo, auto or not."
    nimo_panel_close
}

nimo_auto_set() {
    local want="$1"

    if [ "$want" = "0" ]; then
        NIMO_AUTO=0
        nimo_blank
        nimo_ok "nimo asks again."
        nimo_blank
        return 0
    fi

    if [ "$NIMO_AUTO" = "1" ]; then
        nimo_blank
        nimo_dim "already on — /auto off to turn it back"
        nimo_blank
        return 0
    fi

    nimo_auto_explain
    if nimo_confirm "Stop asking for the rest of this session?"; then
        NIMO_AUTO=1
        nimo_blank
        nimo_ok "Yes to everything, until you leave."
        nimo_blank
    else
        nimo_blank
        nimo_dim "still asking"
        nimo_blank
    fi
    return 0
}

NIMO_COMMAND_WORDS="blank clear tidy desktop downloads screenshots dock wallpaper next prev zen dark light hide empty apps startup duplicates preview clean top doctor setup undo update menu version"

# Everything that starts with what was typed.
nimo_repl_prefix_all() {
    local want="$1" name out=""
    case "$want" in
        *' '*|'') return 1 ;;
    esac
    for name in $NIMO_COMMAND_WORDS; do
        case "$name" in
            "$want"*) out="$out /$name" ;;
        esac
    done
    [ -n "$out" ] || return 1
    printf '%s' "${out# }"
    return 0
}

# The one command that starts with what was typed, when there is exactly one.
nimo_repl_prefix() {
    local want="$1" name hit="" hits=0

    case "$want" in
        *' '*) return 1 ;;   # only single words; phrases are matched properly
        '')    return 1 ;;
    esac

    for name in $NIMO_COMMAND_WORDS; do
        case "$name" in
            "$want"*)
                hits=$((hits + 1))
                hit="$name"
                ;;
        esac
    done

    # two commands start with "d"; that is a question, not an answer
    [ "$hits" -eq 1 ] || return 1
    printf '%s' "$hit"
    return 0
}

# Fix the typos in a whole line, word by word, and hand back what it
# probably said. "clean deskopt" comes back as "clean desktop".
nimo_repl_correct() {
    local phrase="$1" word name shared best best_score out=""

    for word in $phrase; do
        best="$word"
        best_score=0
        for name in clear auto tidy desktop downloads screenshots dock wallpaper zen dark light hide empty apps duplicates preview clean top doctor setup undo update menu; do
            shared=$(nimo_shared_prefix "$word" "$name")
            if [ "$shared" -gt "$best_score" ]; then
                best_score="$shared"
                best="$name"
            fi
        done
        [ "$best_score" -ge 3 ] || best="$word"
        out="$out $best"
    done

    printf '%s' "${out# }"
}

# Run one line. Returns 1 when the answer was "leave".
nimo_repl_do() {
    local line="$1" phrase="" flags="" tok cmd guess

    for tok in $line; do
        case "$tok" in
            -*) flags="$flags $tok" ;;
            *)
                if [ -n "$flags" ]; then
                    flags="$flags $tok"
                else
                    phrase="$phrase $tok"
                fi
                ;;
        esac
    done

    phrase=$(printf '%s' "$phrase" | sed -e 's/^ *//' -e 's/ *$//' -e 's/  */ /g' | tr '[:upper:]' '[:lower:]')
    phrase="${phrase#/}"

    case "$phrase" in
        ''|help|'?'|commands|list)
            nimo_repl_list
            return 0 ;;
        quit|exit|q|bye|leave|stop)
            return 1 ;;
        auto|yolo|"stop asking"|"yes to everything"|autoon|"auto on")
            nimo_auto_set 1
            return 0 ;;
        "auto off"|autooff|"ask me"|manual)
            nimo_auto_set 0
            return 0 ;;
    esac

    cmd=$(nimo_repl_command "$phrase")

    # Half a word is enough when only one command starts that way. /cle is
    # clear, /desk is desktop, /dup is duplicates — the same thing tab would
    # do for you, without needing a terminal that can do tab.
    if [ -z "$cmd" ]; then
        cmd=$(nimo_repl_prefix "$phrase") || cmd=""
    fi

    if [ -z "$cmd" ]; then
        # an ambiguous prefix is a question, and the honest answer is the list
        local starts
        if starts=$(nimo_repl_prefix_all "$phrase"); then
            nimo_blank
            nimo_warn "\"$phrase\" could be $(printf '%s' "$starts" | sed 's/ /, /g; s/\(.*\), /\1 or /')"
            nimo_blank
            return 0
        fi

        local fixed
        fixed=$(nimo_repl_correct "$phrase")

        # the whole line, spelled right, before falling back to one word
        if [ "$fixed" != "$phrase" ] && [ -n "$(nimo_repl_command "$fixed")" ]; then
            nimo_blank
            nimo_warn "nimo does not know \"$phrase\" — did you mean /$fixed?"
            nimo_blank
            return 0
        fi

        guess=$(nimo_repl_guess "$phrase") || guess=""
        nimo_blank
        if [ -n "$guess" ]; then
            nimo_warn "nimo does not know \"$phrase\" — did you mean /$guess?"
        else
            nimo_warn "nimo does not know \"$phrase\""
            nimo_dim "type / to see everything it does know"
        fi
        nimo_blank
        return 0
    fi

    # Each command runs as its own nimo, so nothing one does leaks into the
    # next: the flags, the scan results and the confirmations all start clean.
    local auto=""
    [ "$NIMO_AUTO" = "1" ] && auto="-y"

    # a couple of prompt words stand for a command plus a flag
    # shellcheck disable=SC2086
    bash "$NIMO_SELF" $cmd ${NIMO_INHERIT:-} $auto $flags
    return 0
}

nimo_repl() {
    if [ -t 1 ] && [ "${NIMO_NO_CLEAR:-0}" != "1" ] && [ "${NIMO_QUIET:-0}" != "1" ]; then
        clear
    fi
    if [ "${NIMO_QUIET:-0}" != "1" ]; then
        nimo_face_hello
        printf '\n%s                       nimo%s\n' "$NIMO_C_DIM" "$NIMO_C_RESET"
    fi
    nimo_blank
    if [ "$NIMO_AUTO" = "1" ]; then
        nimo_dim "auto is on — nothing will ask. /auto off to change that."
    else
        nimo_dim "/ to see what it can do"
    fi

    local line prompt

    # readline gives line editing and an up-arrow history; the file makes that
    # history outlive the session, the way a shell's does
    set -o history 2>/dev/null || true
    local hist="$HOME/.nimo/history"
    mkdir -p "$HOME/.nimo" 2>/dev/null
    [ -f "$hist" ] && history -r "$hist" 2>/dev/null

    # A terminal cancels the line you are typing; it does not throw you out of
    # the program. Without this, one stray ctrl-c in the middle of a thought
    # ends the session — and interrupting a command that is running would take
    # the prompt down with it.
    trap ':' INT

    local rc
    while :; do
        if [ "$NIMO_AUTO" = "1" ]; then
            prompt=$(printf '  %snimo%s %sauto%s %s›%s ' \
                "$NIMO_C_BOLD" "$NIMO_C_RESET" \
                "$NIMO_C_YELLOW" "$NIMO_C_RESET" \
                "$NIMO_C_CYAN" "$NIMO_C_RESET")
        else
            prompt=$(printf '  %snimo%s %s›%s ' \
                "$NIMO_C_BOLD" "$NIMO_C_RESET" "$NIMO_C_CYAN" "$NIMO_C_RESET")
        fi
        nimo_blank
        if [ -t 0 ]; then
            IFS= read -r -e -p "$prompt" line
            rc=$?
            if [ "$rc" -gt 128 ]; then
                printf '\n'          # interrupted: forget the line, keep the prompt
                continue
            fi
            [ "$rc" -eq 0 ] || { printf '\n'; break; }
            if [ -n "$line" ]; then
                history -s "$line" 2>/dev/null
                printf '%s\n' "$line" >> "$hist" 2>/dev/null
            fi
        else
            printf '%s' "$prompt"
            IFS= read -r line || { printf '\n'; break; }
            printf '%s\n' "$line"
        fi

        nimo_repl_do "$line" || break
    done

    # keep the last two hundred lines and no more
    if [ -f "$hist" ]; then
        tail -200 "$hist" > "$hist.trim" 2>/dev/null && mv "$hist.trim" "$hist" 2>/dev/null
    fi

    nimo_blank
    return 0
}
