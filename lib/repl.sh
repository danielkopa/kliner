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
nimo_repl_list() {
    nimo_panel_open "what you can type"
    printf '%s%-13s %s%s%s\n' "$NIMO_PAD" "/clear"     "$NIMO_C_DIM" "desktop, downloads, screenshots, dock — you pick" "$NIMO_C_RESET"
    printf '%s%-13s %s%s%s\n' "$NIMO_PAD" "/wallpaper" "$NIMO_C_DIM" "a calmer one, from what macOS ships" "$NIMO_C_RESET"
    printf '%s%-13s %s%s%s\n' "$NIMO_PAD" "/setup"     "$NIMO_C_DIM" "a small, sane macOS setup" "$NIMO_C_RESET"
    printf '%s%-13s %s%s%s\n' "$NIMO_PAD" "/undo"      "$NIMO_C_DIM" "put anything back" "$NIMO_C_RESET"
    nimo_blank
    printf '%s%s%s%s\n' "$NIMO_PAD" "$NIMO_C_DIM" "also  /tidy  /zen  /dark  /hide  /empty  /apps  /duplicates" "$NIMO_C_RESET"
    printf '%s%s%s%s\n' "$NIMO_PAD" "$NIMO_C_DIM" "      /doctor  /top  /preview  /menu  /quit" "$NIMO_C_RESET"
    nimo_blank
    printf '%s%-13s %s%s%s\n' "$NIMO_PAD" "/auto" "$NIMO_C_DIM" "stop asking me — one yes for the whole session" "$NIMO_C_RESET"
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

    if [ -z "$cmd" ]; then
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

    # shellcheck disable=SC2086
    bash "$NIMO_SELF" "$cmd" ${NIMO_INHERIT:-} $auto $flags
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

    # readline gives line editing and an up-arrow history, but only when
    # there is a terminal on the other end
    set -o history 2>/dev/null || true

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
            IFS= read -r -e -p "$prompt" line || { printf '\n'; break; }
            [ -n "$line" ] && history -s "$line" 2>/dev/null
        else
            printf '%s' "$prompt"
            IFS= read -r line || { printf '\n'; break; }
            printf '%s\n' "$line"
        fi

        nimo_repl_do "$line" || break
    done

    nimo_blank
    return 0
}
