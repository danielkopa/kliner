#!/usr/bin/env bash
# nimo :: lib/desktop.sh — a clear desktop, without losing anything.
#
# Everything on your desktop moves into one folder, sorted by what it is.
# Every move is written down, so `min desktop --undo` puts it all back
# exactly where it was.

NIMO_TIDY_DIR_NAME="Tidy"
NIMO_UNDO_DIR="$HOME/.nimo/undo"

# What kind of thing is this? -> Images | Screenshots | Documents | ...
nimo_kind_of() {
    local path="$1" name ext lower
    name=$(basename "$path")

    if [ -d "$path" ]; then
        printf 'Folders'
        return 0
    fi

    lower=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

    case "$lower" in
        screenshot*|"screen shot"*|snímka*|snimka*|cleanshot*)
            printf 'Screenshots'; return 0 ;;
    esac

    ext="${lower##*.}"
    [ "$ext" = "$lower" ] && ext=""

    case "$ext" in
        jpg|jpeg|png|gif|heic|heif|webp|tiff|tif|bmp|svg|ico|raw|cr2|nef)
            printf 'Images' ;;
        mp4|mov|m4v|avi|mkv|webm|wmv|flv)
            printf 'Video' ;;
        mp3|m4a|wav|aiff|aif|flac|aac|ogg)
            printf 'Audio' ;;
        pdf|doc|docx|pages|txt|rtf|rtfd|md|key|numbers|xls|xlsx|csv|tsv|ppt|pptx|epub|odt)
            printf 'Documents' ;;
        zip|tar|gz|tgz|bz2|xz|rar|7z|dmg|pkg|iso)
            printf 'Archives' ;;
        sh|bash|zsh|py|js|mjs|ts|tsx|jsx|json|yml|yaml|html|css|scss|swift|c|h|cpp|hpp|java|rb|go|rs|php|sql|toml|xml)
            printf 'Code' ;;
        app)
            printf 'Apps' ;;
        *)
            printf 'Other' ;;
    esac
}

# A destination that does not step on anything already there.
nimo_free_name() {
    local dir="$1" name="$2" base ext try n
    if [ ! -e "$dir/$name" ]; then
        printf '%s/%s' "$dir" "$name"
        return 0
    fi
    case "$name" in
        *.*) base="${name%.*}"; ext=".${name##*.}" ;;
        *)   base="$name";      ext="" ;;
    esac
    n=2
    while [ "$n" -lt 500 ]; do
        try="$dir/$base $n$ext"
        [ -e "$try" ] || { printf '%s' "$try"; return 0; }
        n=$((n + 1))
    done
    printf '%s/%s %s%s' "$dir" "$base" "$$" "$ext"
}

# Everything on the desktop that nimo is willing to move.
nimo_desktop_items() {
    local desk="$HOME/Desktop"
    [ -d "$desk" ] || return 0
    find "$desk" -mindepth 1 -maxdepth 1 2>/dev/null | while IFS= read -r item; do
        case "$(basename "$item")" in
            .*|"$NIMO_TIDY_DIR_NAME") continue ;;
        esac
        case "$item" in
            *"$(printf '\t')"*) continue ;;
        esac
        printf '%s\n' "$item"
    done
}

# shellcheck disable=SC2120  # the file to undo is optional
nimo_desktop_undo() {
    [ "${NIMO_UNDO_QUIET:-0}" = "1" ] || nimo_header
    nimo_panel_open "put it back"

    local latest="${1:-}"
    [ -n "$latest" ] || latest=$(ls -1 "$NIMO_UNDO_DIR"/desktop-*.tsv 2>/dev/null | tail -1)

    if [ -z "$latest" ]; then
        nimo_dim "nimo has not tidied your desktop yet — nothing to undo"
        nimo_panel_close
        nimo_blank
        return 0
    fi

    nimo_dim "from $(basename "$latest")"
    nimo_blank

    local back=0 missing=0 src dst
    while IFS=$'\t' read -r src dst; do
        [ -n "${src:-}" ] || continue
        [ -n "${dst:-}" ] || continue
        if [ -e "$dst" ] && [ ! -e "$src" ]; then
            mv "$dst" "$src" 2>/dev/null && back=$((back + 1))
        else
            missing=$((missing + 1))
        fi
    done < "$latest"

    # tidy up the folders we emptied, but never anything with content left
    find "$HOME/Desktop/$NIMO_TIDY_DIR_NAME" -type d -depth 2>/dev/null \
        | while IFS= read -r d; do rmdir "$d" 2>/dev/null || true; done

    nimo_ok "$(nimo_plural "$back" file) back on your desktop"
    [ "$missing" -gt 0 ] && nimo_dim "$missing were moved or renamed since, so nimo left them alone"
    nimo_panel_close
    nimo_blank
    return 0
}

nimo_cmd_desktop() {
    if [ "${NIMO_UNDO:-0}" = "1" ]; then
        nimo_desktop_undo
        return 0
    fi

    nimo_header

    local desk="$HOME/Desktop"
    if [ ! -d "$desk" ]; then
        nimo_warn "you do not seem to have a Desktop folder"
        nimo_blank
        return 1
    fi

    local items count
    items=$(nimo_desktop_items)
    count=$(nimo_line_count "$items")

    nimo_panel_open "your desktop"

    if [ "$count" -eq 0 ]; then
        nimo_ok "Your desktop is already clear."
        nimo_panel_close
        nimo_blank
        return 0
    fi

    # count them by kind, keeping bash 3.2 in mind: no associative arrays
    local kinds="Screenshots Images Documents Video Audio Archives Code Apps Folders Other"
    local kind n item total=0
    for kind in $kinds; do
        n=0
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            [ "$(nimo_kind_of "$item")" = "$kind" ] && n=$((n + 1))
        done <<EOF
$items
EOF
        if [ "$n" -gt 0 ]; then
            nimo_row "$kind" "$(nimo_plural "$n" item)" ""
            total=$((total + n))
        fi
    done

    nimo_blank
    nimo_rule
    nimo_total "On your desktop" "$(nimo_plural "$total" item)"
    nimo_panel_close

    nimo_blank
    nimo_dim "everything moves into  Desktop/$NIMO_TIDY_DIR_NAME/<kind>/"
    nimo_dim "nothing is deleted, nothing is renamed, and  min desktop --undo  puts it all back"
    nimo_blank

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "preview only — your desktop was not touched"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "Clear your desktop?"; then
        nimo_blank
        nimo_dim "your desktop is exactly as it was"
        nimo_blank
        return 0
    fi

    mkdir -p "$NIMO_UNDO_DIR" 2>/dev/null
    local log
    log="$NIMO_UNDO_DIR/desktop-$(date +%Y%m%d-%H%M%S).tsv"
    : > "$log"

    local root="$desk/$NIMO_TIDY_DIR_NAME" moved=0 failed=0 dest target
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        kind=$(nimo_kind_of "$item")
        dest="$root/$kind"
        mkdir -p "$dest" 2>/dev/null
        target=$(nimo_free_name "$dest" "$(basename "$item")")
        if mv "$item" "$target" 2>/dev/null; then
            printf '%s\t%s\n' "$item" "$target" >> "$log"
            moved=$((moved + 1))
        else
            failed=$((failed + 1))
        fi
    done <<EOF
$items
EOF

    nimo_blank
    nimo_ok "Your desktop is clear — $(nimo_plural "$moved" item) filed away"
    nimo_dim "Desktop/$NIMO_TIDY_DIR_NAME/"
    [ "$failed" -gt 0 ] && nimo_warn "$failed could not be moved and were left where they are"
    nimo_blank
    nimo_dim "changed your mind?  min desktop --undo"
    nimo_blank
    return 0
}
