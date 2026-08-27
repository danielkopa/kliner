#!/usr/bin/env bash
# nimo :: lib/desktop.sh — a clear desktop, without losing anything.
#
# Everything on your desktop moves into one folder, sorted by what it is.
# Every move is written down, so `min desktop --undo` puts it all back
# exactly where it was.

NIMO_TIDY_DIR_NAME="Tidy"

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

# Everything in a folder that nimo is willing to move.
nimo_folder_items() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | while IFS= read -r item; do
        case "$(basename "$item")" in
            .*|"$NIMO_TIDY_DIR_NAME") continue ;;
        esac
        case "$item" in
            *"$(printf '\t')"*) continue ;;
        esac
        printf '%s\n' "$item"
    done
}

# Undo one sorting run.
#
#   $1  which sorter: desktop, downloads, screenshots — or any
#   $2  an exact log to replay, when the caller already picked one
#
# The tag matters. The logs are named by kind and then by the second they were
# made in, and the newest is taken from the end of a sorted glob — so a single
# glob across every kind quietly hands "screenshots-…" to `min desktop --undo`,
# because s sorts after d. Each command undoes its own kind.
nimo_sort_undo() {
    local tag="${1:-any}" latest="${2:-}"

    [ "${NIMO_UNDO_QUIET:-0}" = "1" ] || nimo_header
    nimo_panel_open "put it back"

    if [ -z "$latest" ]; then
        case "$tag" in
            any) latest=$(ls -1 "$NIMO_UNDO_DIR"/desktop-*.tsv \
                                "$NIMO_UNDO_DIR"/downloads-*.tsv \
                                "$NIMO_UNDO_DIR"/screenshots-*.tsv 2>/dev/null | tail -1) ;;
            *)   latest=$(ls -1 "$NIMO_UNDO_DIR/$tag"-*.tsv 2>/dev/null | tail -1) ;;
        esac
    fi

    if [ -z "$latest" ] || [ ! -f "$latest" ]; then
        nimo_dim "nimo has not moved anything here yet — nothing to undo"
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

    # take away the folders we emptied, never one with anything left in it
    local room
    for room in "$HOME/Desktop/$NIMO_TIDY_DIR_NAME" \
                "$HOME/Downloads/$NIMO_TIDY_DIR_NAME" \
                "$HOME/Pictures/Screenshots"; do
        [ -d "$room" ] || continue
        find "$room" -type d -depth 2>/dev/null \
            | while IFS= read -r d; do rmdir "$d" 2>/dev/null || true; done
    done

    nimo_ok "$(nimo_plural "$back" file) put back"
    [ "$missing" -gt 0 ] && nimo_dim "$missing were moved or renamed since, so nimo left them alone"
    nimo_panel_close
    nimo_blank
    return 0
}

# `min undo` hands over an exact log; the kind is already decided by then.
# shellcheck disable=SC2120  # the log to replay is optional
nimo_desktop_undo() {
    nimo_sort_undo any "${1:-}"
}

# The one sorter behind /desktop, /downloads and /screenshots.
#
#   $1 the folder to sort        $2 what to call it out loud
#   $3 where the sorted copy goes    $4 the undo log's prefix
nimo_sort_folder() {
    local src="$1" title="$2" root="$3" tag="$4"

    if [ ! -d "$src" ]; then
        nimo_warn "there is no $src to sort"
        nimo_blank
        return 1
    fi

    local items count
    items=$(nimo_folder_items "$src")
    count=$(nimo_line_count "$items")

    nimo_panel_open "$title"

    if [ "$count" -eq 0 ]; then
        nimo_ok "Nothing to sort — it is already clear."
        nimo_panel_close
        nimo_blank
        return 0
    fi

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
    nimo_total "In there" "$(nimo_plural "$total" item)"
    nimo_panel_close

    nimo_blank
    nimo_dim "everything moves into  ${root#$HOME/}/<kind>/"
    nimo_dim "nothing is deleted, nothing is renamed, and  min $tag --undo  puts it all back"
    nimo_blank

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "preview only — nothing was moved"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "Sort $(nimo_plural "$total" item)?"; then
        nimo_blank
        nimo_dim "left exactly as it was"
        nimo_blank
        return 0
    fi

    mkdir -p "$NIMO_UNDO_DIR" 2>/dev/null
    local log
    log=$(nimo_free_file "$NIMO_UNDO_DIR/$tag-$(date +%Y%m%d-%H%M%S)" .tsv)
    : > "$log"

    local moved=0 failed=0 dest target
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
    nimo_ok "Sorted — $(nimo_plural "$moved" item) filed away"
    nimo_dim "${root#$HOME/}/"
    [ "$failed" -gt 0 ] && nimo_warn "$failed could not be moved and were left where they are"
    nimo_blank
    nimo_dim "changed your mind?  min $tag --undo"
    nimo_blank
    return 0
}

nimo_cmd_desktop() {
    if [ "${NIMO_UNDO:-0}" = "1" ]; then
        nimo_sort_undo desktop
        return 0
    fi
    nimo_header
    nimo_sort_folder "$HOME/Desktop" "your desktop" \
        "$HOME/Desktop/$NIMO_TIDY_DIR_NAME" desktop
}

nimo_cmd_downloads() {
    if [ "${NIMO_UNDO:-0}" = "1" ]; then
        nimo_sort_undo downloads
        return 0
    fi
    nimo_header
    nimo_sort_folder "$HOME/Downloads" "your downloads" \
        "$HOME/Downloads/$NIMO_TIDY_DIR_NAME" downloads
}

# Screenshots end up wherever they were taken. This gathers them from the
# usual scattering grounds into one folder, and nowhere else.
nimo_cmd_screenshots() {
    if [ "${NIMO_UNDO:-0}" = "1" ]; then
        nimo_sort_undo screenshots
        return 0
    fi

    nimo_header

    local room="$HOME/Pictures/Screenshots" found="" item where
    for where in "$HOME/Desktop" "$HOME/Downloads" "$HOME/Documents"; do
        [ -d "$where" ] || continue
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            [ "$(nimo_kind_of "$item")" = "Screenshots" ] || continue
            found="$found$item
"
        done <<EOF
$(nimo_folder_items "$where")
EOF
    done

    local count
    count=$(nimo_line_count "$found")

    nimo_panel_open "your screenshots"

    if [ "$count" -eq 0 ]; then
        nimo_ok "No loose screenshots — nothing to gather."
        nimo_panel_close
        nimo_blank
        return 0
    fi

    local shown=0
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        shown=$((shown + 1))
        [ "$shown" -gt 8 ] && continue
        where="${item%/*}"
        nimo_row "$(basename "$item")" "" "${where#$HOME/}"
    done <<EOF
$found
EOF
    [ "$count" -gt 8 ] && nimo_dim "… and $((count - 8)) more"

    nimo_blank
    nimo_rule
    nimo_total "Loose screenshots" "$(nimo_plural "$count" file)"
    nimo_panel_close

    nimo_blank
    nimo_dim "they all move into  Pictures/Screenshots/"
    nimo_dim "nothing is deleted, and  min screenshots --undo  puts them back"
    nimo_blank

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "preview only — nothing was moved"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "Gather $(nimo_plural "$count" screenshot)?"; then
        nimo_blank
        nimo_dim "left exactly where they are"
        nimo_blank
        return 0
    fi

    mkdir -p "$room" "$NIMO_UNDO_DIR" 2>/dev/null
    local log target moved=0 failed=0
    log=$(nimo_free_file "$NIMO_UNDO_DIR/screenshots-$(date +%Y%m%d-%H%M%S)" .tsv)
    : > "$log"

    while IFS= read -r item; do
        [ -n "$item" ] || continue
        target=$(nimo_free_name "$room" "$(basename "$item")")
        if mv "$item" "$target" 2>/dev/null; then
            printf '%s\t%s\n' "$item" "$target" >> "$log"
            moved=$((moved + 1))
        else
            failed=$((failed + 1))
        fi
    done <<EOF
$found
EOF

    nimo_blank
    nimo_ok "Gathered — $(nimo_plural "$moved" screenshot) in one place"
    nimo_dim "Pictures/Screenshots/"
    [ "$failed" -gt 0 ] && nimo_warn "$failed could not be moved"
    nimo_blank
    return 0
}
