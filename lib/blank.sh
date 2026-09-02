#!/usr/bin/env bash
# nimo :: lib/blank.sh — empty a file without losing what was in it.
#
# `> notes.txt` in a shell empties a file in a keystroke, and there is no way
# back from it. nimo does the same thing, except it puts a copy of the contents
# in ~/.nimo/undo first — so emptying a document is a decision you can change
# your mind about, like everything else here.

NIMO_BLANK_STORE="$HOME/.nimo/undo/files"

nimo_cmd_blank() {
    nimo_header

    local target="${NIMO_TARGET:-}"

    if [ -z "$target" ]; then
        nimo_panel_open "empty a file"
        nimo_warn "nimo needs to know which file"
        nimo_blank
        nimo_dim "min blank notes.txt"
        nimo_dim "or drag the file into the terminal after typing  min blank"
        nimo_panel_close
        return 1
    fi

    # Every path becomes absolute before anything looks at it.
    #
    # The guard that keeps nimo inside your home folder compares against
    # $HOME, and a relative path never starts with it — so `min blank
    # Documents/notes.txt`, typed from your home folder, was refused as
    # "outside your home folder". The most natural way to use the command was
    # the one way it could not be used.
    # A quoted tilde is a literal tilde: the shell expanded nothing, so nimo
    # has to. That is the point of these two lines, not an oversight.
    # shellcheck disable=SC2088
    case "$target" in
        /*)  ;;
        "~") target="$HOME" ;;
        "~/"*) target="$HOME/${target#\~/}" ;;
        *)   target="$PWD/$target" ;;
    esac
    # one spelling, the same one the guard normalises to
    target=$(nimo_norm_path "$target")

    if [ ! -e "$target" ]; then
        nimo_warn "there is no $target"
        nimo_blank
        return 1
    fi

    if [ -d "$target" ]; then
        nimo_warn "$target is a folder, nimo empties files, not folders"
        nimo_dim "for a folder full of things:  min clear"
        nimo_blank
        return 1
    fi

    # A link is checked as the name you typed and emptied as the file it
    # points at. `~/notes.txt -> /etc/hosts` passes a guard that only reads
    # the path, and then truncates something nimo has no business touching.
    if [ -L "$target" ]; then
        nimo_warn "$(basename "$target") is a link, nimo will not empty what it points at"
        nimo_dim "name the file itself if that is what you meant"
        nimo_blank
        return 1
    fi

    if nimo_is_protected "$target"; then
        nimo_err "that is outside your home folder, nimo will not touch it"
        nimo_blank
        return 1
    fi

    local bytes
    bytes=$(wc -c < "$target" 2>/dev/null | tr -d ' ')

    nimo_panel_open "empty a file"
    local where="${target%/*}"
    nimo_row "$(basename "$target")" "$(nimo_human_bytes "${bytes:-0}")" "${where#$HOME/}"
    nimo_blank

    if [ "${bytes:-0}" -eq 0 ]; then
        nimo_ok "Already empty."
        nimo_panel_close
        nimo_blank
        return 0
    fi

    nimo_dim "the file stays where it is, with nothing in it"
    nimo_dim "a copy of what was in it goes to ~/.nimo/undo, so  min undo  can put it back"
    nimo_panel_close
    nimo_blank

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "preview only, nothing was emptied"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "Empty $(basename "$target")?"; then
        nimo_blank
        nimo_dim "left as it was"
        nimo_blank
        return 0
    fi

    mkdir -p "$NIMO_BLANK_STORE" "$NIMO_UNDO_DIR" 2>/dev/null
    local keep log
    keep=$(nimo_free_file "$NIMO_BLANK_STORE/$(date +%Y%m%d-%H%M%S)-$(basename "$target")" "")
    if ! cp "$target" "$keep" 2>/dev/null; then
        nimo_err "nimo could not keep a copy, so it will not empty the file"
        nimo_blank
        return 1
    fi

    log=$(nimo_free_file "$NIMO_UNDO_DIR/blank-$(date +%Y%m%d-%H%M%S)" .tsv)
    printf '%s\t%s\n' "$target" "$keep" > "$log"

    : > "$target"

    nimo_blank
    nimo_ok "Empty, $(nimo_human_bytes "${bytes:-0}") of it kept"
    nimo_dim "put it back with  min undo"
    nimo_blank
    return 0
}

# Put the contents back, from the copy taken before emptying.
nimo_blank_undo() {
    [ "${NIMO_UNDO_QUIET:-0}" = "1" ] || nimo_header
    nimo_panel_open "put it back"

    local latest="${1:-}"
    [ -n "$latest" ] || latest=$(nimo_newest "$NIMO_UNDO_DIR"/blank-*.tsv) || latest=""

    if [ -z "$latest" ] || [ ! -f "$latest" ]; then
        nimo_dim "nimo has not emptied a file yet, nothing to undo"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    local file keep back=0
    while IFS=$'\t' read -r file keep; do
        [ -n "${file:-}" ] || continue
        [ -f "${keep:-}" ] || continue
        if cp "$keep" "$file" 2>/dev/null; then
            back=$((back + 1))
            nimo_ok "$(basename "$file") has its contents again"
        else
            nimo_warn "could not write back to $file"
        fi
    done < "$latest"

    [ "$back" -eq 0 ] && nimo_dim "nothing to put back"
    nimo_panel_close
    nimo_blank
    return 0
}
