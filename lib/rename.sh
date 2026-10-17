#!/usr/bin/env bash
# nimo :: lib/rename.sh — give a file a new name, and a way back to the old one.
#
# `mv notes.txt "Notes 2026.txt"` renames a file in a keystroke, and on a
# folder where that name is already taken it quietly replaces the file that
# had it. nimo renames the same way Finder does: in the same folder, never on
# top of anything, and written down first, so `min undo` can put the old name
# back.

nimo_cmd_rename() {
    if [ "${NIMO_UNDO:-0}" = "1" ]; then
        nimo_rename_undo
        return $?
    fi

    nimo_header

    local target="${NIMO_TARGET:-}" to="${NIMO_TO:-}"

    if [ -z "$target" ]; then
        nimo_panel_open "rename a file"
        nimo_warn "nimo needs to know which file"
        nimo_blank
        nimo_dim "min rename notes.txt \"Notes 2026.txt\""
        nimo_panel_close
        return 1
    fi

    # The same spellings `min blank` takes: a relative path, ./, ~ and the
    # whole path all mean the file you meant.
    # shellcheck disable=SC2088
    case "$target" in
        /*)  ;;
        "~") target="$HOME" ;;
        "~/"*) target="$HOME/${target#\~/}" ;;
        *)   target="$PWD/$target" ;;
    esac
    target=$(nimo_norm_path "$target")
    # a folder named with a slash on the end is still that folder
    while [ "${#target}" -gt 1 ] && [ "${target%/}" != "$target" ]; do target="${target%/}"; done

    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        nimo_warn "there is no $target"
        nimo_blank
        return 1
    fi

    if nimo_is_protected "$target"; then
        nimo_err "that is outside your home folder, nimo will not touch it"
        nimo_blank
        return 1
    fi

    local dir="${target%/*}" was="${target##*/}"
    [ -n "$dir" ] || dir="/"

    # The folders macOS and Windows keep for themselves. Renamed, the Desktop
    # is no longer the desktop, and everything that looks for it looks at
    # nothing.
    if [ "$dir" = "$(nimo_norm_path "$HOME")" ]; then
        case "$was" in
            Desktop|Documents|Downloads|Library|Pictures|Music|Movies|Videos|Public|Applications|AppData|OneDrive|Sites)
                nimo_err "$was is one of the folders your computer keeps for itself, nimo will not rename it"
                nimo_blank
                return 1
                ;;
        esac
    fi

    # A new name is a name, not a route: it stays in the same folder.
    local tab bad=""
    tab=$(printf '\t')
    case "$to" in
        "")        bad="nimo needs the new name, as in  min rename $was \"new name\"" ;;
        *"$tab"*|*"
"*)                bad="nimo cannot write that name down, so it will not use it" ;;
        .|..)      bad="that name belongs to the folder itself" ;;
        */*)       bad="a name cannot have / in it" ;;
        .*)        bad="a name that starts with a dot hides the file, nimo will not do that" ;;
    esac
    if [ -z "$bad" ] && nimo_is_macos; then
        case "$to" in *:*) bad="a name cannot have : in it on a Mac" ;; esac
    fi
    if [ -z "$bad" ] && nimo_is_windows; then
        case "$to" in
            *\\*|*:*|*\**|*\?*|*\"*|*\<*|*\>*|*\|*) bad='a name cannot have any of \ : * ? " < > | in it on Windows' ;;
            *" "|*.) bad="Windows drops a space or a dot at the end of a name, so nimo will not use one" ;;
        esac
    fi
    if [ -z "$bad" ] && [ "$(printf '%s' "$to" | wc -c | tr -d ' ')" -gt 255 ]; then
        bad="that name is longer than a file name can be"
    fi
    if [ -n "$bad" ]; then
        nimo_err "$bad"
        nimo_blank
        return 1
    fi

    # Where the file was found, and where nimo writes it down, are the same
    # log `min undo` reads — so a path it cannot write down is one it will
    # not change.
    case "$target" in
        *"$tab"*|*"
"*)
            nimo_err "nimo cannot write that name down, so it will not rename it"
            nimo_blank
            return 1
            ;;
    esac

    local dest="$dir/$to"
    [ "$dir" = "/" ] && dest="/$to"

    nimo_panel_open "rename a file"
    printf '%s%s\n' "$NIMO_PAD" "$was"
    printf '%s%s→%s %s\n' "$NIMO_PAD" "$NIMO_C_DIM" "$NIMO_C_RESET" "$to"
    nimo_dim "in ${dir#$HOME/}"
    nimo_blank

    if [ "$to" = "$was" ]; then
        nimo_ok "Already called that."
        nimo_panel_close
        nimo_blank
        return 0
    fi

    # Taken is taken — unless the name that is "taken" is this very file,
    # which is what a Mac says about notes.txt when you ask for Notes.txt.
    local just_case=0
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ "$target" -ef "$dest" ] && [ ! -L "$dest" ]; then
            just_case=1
        else
            nimo_err "there is already a $to there, nimo will not replace it"
            nimo_panel_close
            nimo_blank
            return 1
        fi
    fi

    nimo_dim "only the name changes, the file stays where it is"
    nimo_dim "min undo  puts the old name back"
    nimo_panel_close
    nimo_blank

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "preview only, nothing was renamed"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "Rename $was to $to?"; then
        nimo_blank
        nimo_dim "left as it was"
        nimo_blank
        return 0
    fi

    mkdir -p "$NIMO_UNDO_DIR" 2>/dev/null
    local log
    log=$(nimo_free_file "$NIMO_UNDO_DIR/rename-$(date +%Y%m%d-%H%M%S)" .tsv)
    # Written down before the name changes, as every move nimo makes is.
    printf '%s\t%s\n' "$target" "$dest" > "$log"

    if ! nimo_rename_move "$target" "$dest" "$just_case"; then
        nimo_undo_drop_last "$log"
        nimo_err "the name could not be changed, the file is as it was"
        nimo_blank
        return 1
    fi
    # A folder nimo sorted things into, renamed, is still the folder every
    # record of that sorting points into: the records follow it, so
    # `min desktop --undo` still finds every file under its new name.
    [ -d "$dest" ] && nimo_rename_follow "$target" "$dest" "$log"

    nimo_ok "Renamed to $to"
    nimo_dim "changed your mind?  min rename --undo"
    nimo_blank
    return 0
}

# The one move, done so that nothing is ever stepped on.
#
#   $3  1 when the new name is the old one in other letters (Notes for notes)
#
# `mv -n` never replaces what is already there — which on a Mac includes the
# very file being renamed, when all that changes is a capital letter. Those go
# through a name nobody has, in the same folder, and then to the new one.
nimo_rename_move() {
    local from="$1" to="$2" just_case="${3:-0}" step
    if [ "$just_case" = "1" ]; then
        step=$(nimo_free_name "${from%/*}" ".nimo-rename-$$")
        mv -n "$from" "$step" 2>/dev/null || return 1
        [ -e "$step" ] || [ -L "$step" ] || return 1
        if ! mv -n "$step" "$to" 2>/dev/null || [ -e "$step" ] || [ -L "$step" ]; then
            mv -n "$step" "$from" 2>/dev/null
            return 1
        fi
        return 0
    fi
    mv -n "$from" "$to" 2>/dev/null || return 1
    # mv -n says nothing when it declines; the file still being where it was
    # is how that is told apart from a rename
    { [ -e "$from" ] || [ -L "$from" ]; } && [ ! "$from" -ef "$to" ] && return 1
    { [ -e "$to" ] || [ -L "$to" ]; } || return 1
    return 0
}

# Every record of what nimo moved, pointed at a folder's new name.
#
#   $1 the folder as it was   $2 as it is now   $3 a log to leave alone
#
# A path in a record is the folder itself or something inside it; both are
# rewritten, and nothing else is — a folder called Tidy 2 is not inside Tidy.
# The paths go to awk through its environment, which leaves a backslash in a
# name a backslash; -v would read it as an escape.
nimo_rename_follow() {
    local from="$1" to="$2" skip="${3:-}" log tmp
    for log in "$NIMO_UNDO_DIR"/*.tsv; do
        [ -f "$log" ] || continue
        [ "$log" = "$skip" ] && continue
        grep -qF "$from" "$log" 2>/dev/null || continue
        tmp="$log.follow-$$"
        if FROM="$from" TO="$to" awk 'BEGIN { FS = OFS = "\t"; a = ENVIRON["FROM"]; b = ENVIRON["TO"] }
            { for (i = 1; i <= NF; i++) {
                  if ($i == a) $i = b
                  else if (index($i, a "/") == 1) $i = b substr($i, length(a) + 1)
              }
              print }' "$log" > "$tmp" 2>/dev/null; then
            # the same age as before: which record is newest is by date
            touch -r "$log" "$tmp" 2>/dev/null
            mv "$tmp" "$log" 2>/dev/null || true
        fi
    done
    return 0
}

# Put the old names back, from a log — the newest, unless one is handed over.
# A name that has changed again since, or a file that has gone, is left
# exactly as it is.
nimo_rename_undo() {
    [ "${NIMO_UNDO_QUIET:-0}" = "1" ] || nimo_header
    nimo_panel_open "put the name back"

    local latest="${1:-}" spend=0
    if [ -z "$latest" ]; then
        latest=$(nimo_newest "$NIMO_UNDO_DIR"/rename-*.tsv) || latest=""
        spend=1
    fi

    if [ -z "$latest" ] || [ ! -f "$latest" ] || [ "$(nimo_file_lines "$latest")" -eq 0 ]; then
        nimo_dim "no name nimo changed is left to put back"
        nimo_panel_close
        nimo_blank
        return 1
    fi

    local back=0 missing=0 src dst just_case names=""
    while IFS=$'\t' read -r src dst; do
        [ -n "${src:-}" ] && [ -n "${dst:-}" ] || continue
        if ! { [ -e "$dst" ] || [ -L "$dst" ]; }; then
            missing=$((missing + 1)); continue
        fi
        just_case=0
        if [ -e "$src" ] || [ -L "$src" ]; then
            if [ "$src" -ef "$dst" ] && [ ! -L "$src" ]; then just_case=1
            else missing=$((missing + 1)); continue
            fi
        fi
        if nimo_rename_move "$dst" "$src" "$just_case"; then
            [ -d "$src" ] && nimo_rename_follow "$dst" "$src" "$latest"
            back=$((back + 1))
            names="$names${src##*/}
"
        else
            missing=$((missing + 1))
        fi
    done < "$latest"

    # Replayed, so it is not a thing to undo twice: kept in done/, not
    # deleted. Before a word is said about it, because whoever reads this may
    # stop reading at the first line, and the log is spent either way.
    [ "$spend" = "1" ] && nimo_undo_spend "$latest"

    local name
    while IFS= read -r name; do
        [ -n "$name" ] && nimo_ok "Back to $name"
    done <<NAMES
$names
NAMES
    [ "$back" -eq 0 ] && nimo_dim "nothing was put back"
    [ "$missing" -gt 0 ] && nimo_dim "$(nimo_plural "$missing" name) changed again since, or the file is gone, so nimo left it alone"
    nimo_panel_close
    nimo_blank
    [ "$back" -gt 0 ]
}
