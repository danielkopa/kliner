#!/usr/bin/env bash
# nimo :: lib/desktop.sh — a clear desktop, without losing anything.
#
# Everything on your desktop moves into one folder, sorted by what it is.
# Every move is written down, so `min desktop --undo` puts it all back
# exactly where it was.

NIMO_TIDY_DIR_NAME="Tidy"

# Which folder should this end up in?
#
#   kind    Images, Documents, Screenshots …  (what it is)
#   letter  A, B, C … and # for the rest      (what it is called)
#   date    2026-08, 2026-07 …                (when it was last touched)
#
# One sorter, three ways of deciding — because "by what it is" is the right
# answer for a desktop and the wrong one for four hundred invoices.
# No subshells in here, and none in nimo_kind_of either.
#
# `basename` and `tr` are each a fork, and this runs once per file. Two
# thousand downloads meant four thousand forks before nimo had printed a
# single row, and `min downloads --dry-run` sat there for half a minute.
# `${path##*/}` is the same answer, and `shopt -s nocasematch` does what the
# `tr` was for without leaving the shell.
# Two shapes of every classifier: one that sets a variable, and one that
# prints. `$( )` is a fork, and these run once per file — so everything hot
# calls the setter and nothing forks at all.
nimo_bucket_of() { nimo_bucket_set "$1"; printf '%s' "$NIMO_BUCKET"; }
nimo_kind_of()   { nimo_kind_set "$1";   printf '%s' "$NIMO_KIND"; }

nimo_bucket_set() {
    local path="$1" first stamp

    case "${NIMO_BY:-kind}" in
        letter)
            first="${path##*/}"
            first="${first:0:1}"
            case "$first" in
                a|A) first=A ;; b|B) first=B ;; c|C) first=C ;; d|D) first=D ;;
                e|E) first=E ;; f|F) first=F ;; g|G) first=G ;; h|H) first=H ;;
                i|I) first=I ;; j|J) first=J ;; k|K) first=K ;; l|L) first=L ;;
                m|M) first=M ;; n|N) first=N ;; o|O) first=O ;; p|P) first=P ;;
                q|Q) first=Q ;; r|R) first=R ;; s|S) first=S ;; t|T) first=T ;;
                u|U) first=U ;; v|V) first=V ;; w|W) first=W ;; x|X) first=X ;;
                y|Y) first=Y ;; z|Z) first=Z ;;
                *)   first='#' ;;
            esac
            NIMO_BUCKET="$first"
            return 0 ;;
        date)
            # the one classifier that still costs a process per file: nothing
            # in the shell knows a file's date
            stamp=$(date -r "$path" +%Y-%m 2>/dev/null) || stamp=""
            [ -n "$stamp" ] || stamp="undated"
            NIMO_BUCKET="$stamp"
            return 0 ;;
        *)
            nimo_kind_set "$path"
            NIMO_BUCKET="$NIMO_KIND"
            return 0 ;;
    esac
}

# The buckets present in an already-decided list, in the order to list them.
#
# It reads the answers rather than working them out again: kinds have a fixed
# order worth keeping, and letters and dates are whatever turned up.
nimo_buckets_in() {
    local sorted="$1" bucket
    case "${NIMO_BY:-kind}" in
        kind)
            printf '%s\n' Screenshots Images Documents Video Audio Archives Code Apps Folders Other
            return 0 ;;
    esac
    printf '%s\n' "$sorted" | cut -f1 | grep -v '^$' | sort -u
}

# What kind of thing is this? -> Images | Screenshots | Documents | ...
nimo_kind_set() {
    local path="$1" name ext

    if [ -d "$path" ]; then
        NIMO_KIND=Folders
        return 0
    fi

    name="${path##*/}"

    # `shopt` is a builtin, so this costs nothing; `tr` in a $( ) is a fork,
    # and used to cost one per file. nimo never wants nocasematch on anywhere
    # else, so it is simply turned off again rather than saved and replayed —
    # which would need a $( ) of its own and put the fork straight back.
    shopt -s nocasematch 2>/dev/null

    case "$name" in
        screenshot*|"screen shot"*|snímka*|snimka*|cleanshot*)
            shopt -u nocasematch 2>/dev/null
            NIMO_KIND=Screenshots
            return 0 ;;
    esac

    ext="${name##*.}"
    [ "$ext" = "$name" ] && ext=""

    case "$ext" in
        jpg|jpeg|png|gif|heic|heif|webp|tiff|tif|bmp|svg|ico|raw|cr2|nef)
            NIMO_KIND=Images ;;
        mp4|mov|m4v|avi|mkv|webm|wmv|flv)
            NIMO_KIND=Video ;;
        mp3|m4a|wav|aiff|aif|flac|aac|ogg)
            NIMO_KIND=Audio ;;
        pdf|doc|docx|pages|txt|rtf|rtfd|md|key|numbers|xls|xlsx|csv|tsv|ppt|pptx|epub|odt)
            NIMO_KIND=Documents ;;
        zip|tar|gz|tgz|bz2|xz|rar|7z|dmg|pkg|iso)
            NIMO_KIND=Archives ;;
        sh|bash|zsh|py|js|mjs|ts|tsx|jsx|json|yml|yaml|html|css|scss|swift|c|h|cpp|hpp|java|rb|go|rs|php|sql|toml|xml)
            NIMO_KIND=Code ;;
        app)
            NIMO_KIND=Apps ;;
        *)
            NIMO_KIND=Other ;;
    esac
    shopt -u nocasematch 2>/dev/null
    return 0
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
#
# A browser writes "film.mp4.download" while it is still fetching, and moving
# that out from under it breaks the download and leaves you with half a file
# under a name you will never recognise. Anything still arriving is left alone.
nimo_still_arriving() {
    case "$1" in
        *.download|*.crdownload|*.part|*.partial|*.opdownload|*.aria2|*.tmp|*.!ut)
            return 0 ;;
    esac
    return 1
}

# How many nimo deliberately left where they are, so it can say so out loud.
# Six files sorted out of seven, with the seventh still sitting there and no
# word about why, reads like nimo missed one.
nimo_arriving_count() {
    local dir="$1" item n=0
    [ -d "$dir" ] || { printf '0'; return 0; }
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        case "$(basename "$item")" in .*) continue ;; esac
        nimo_still_arriving "$item" && n=$((n + 1))
    done <<EOF
$(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null)
EOF
    printf '%s' "$n"
}

# Two subshells per file used to live in this loop — a `basename` and a
# `$(printf '\t')` — which is four thousand forks on a folder of two thousand
# things, before nimo has decided anything about any of them.
nimo_folder_items() {
    local dir="$1" item name
    [ -d "$dir" ] || return 0
    find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | while IFS= read -r item; do
        # A name with a newline in it arrives here as two lines: the half
        # before it, which is not a path to anything, and the half after,
        # which is not even absolute. Both are dropped — nimo moves what it
        # can name in a log it can read back, and says how many it left.
        case "$item" in
            "$dir"/*) ;;
            *) continue ;;
        esac
        [ -e "$item" ] || continue

        name="${item##*/}"
        case "$name" in
            .*|"$NIMO_TIDY_DIR_NAME") continue ;;
        esac
        nimo_still_arriving "$item" && continue
        case "$item" in
            *$'\t'*) continue ;;
        esac
        printf '%s\n' "$item"
    done
}

# How many nimo will not touch because their names cannot survive a line in a
# log: a newline or a tab in the name. Counted so the panel can say so, rather
# than quietly sorting fewer things than are in the folder.
nimo_unnameable_count() {
    local dir="$1" lines nulls
    [ -d "$dir" ] || { printf '0'; return 0; }
    lines=$(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | grep -c . 2>/dev/null)
    nulls=$(find "$dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | tr -dc '\0' | wc -c | tr -d ' ')
    case "${lines:-}" in ''|*[!0-9]*) lines=0 ;; esac
    case "${nulls:-}" in ''|*[!0-9]*) nulls=0 ;; esac
    # every newline inside a name adds a line that is not a file
    local extra=$((lines - nulls))
    [ "$extra" -lt 0 ] && extra=0

    local item tabs=0
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        case "$item" in *$'\t'*) tabs=$((tabs + 1)) ;; esac
    done <<INNER
$(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null)
INNER

    # one newline in a name is one extra line and one file nimo skips
    printf '%s' "$((extra + tabs))"
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
            any) latest=$(nimo_newest "$NIMO_UNDO_DIR"/desktop-*.tsv \
                                      "$NIMO_UNDO_DIR"/downloads-*.tsv \
                                      "$NIMO_UNDO_DIR"/screenshots-*.tsv) || latest="" ;;
            *)   latest=$(nimo_newest "$NIMO_UNDO_DIR/$tag"-*.tsv) || latest="" ;;
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
    for room in "$(nimo_desktop_dir)/$NIMO_TIDY_DIR_NAME" \
                "$(nimo_downloads_dir)/$NIMO_TIDY_DIR_NAME" \
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

    # Work out each item's bucket once.
    #
    # This used to be a loop over buckets around a loop over items, with a
    # `nimo_bucket_of` — a subshell, a basename and a tr — inside both. Ten
    # buckets and two thousand downloads meant twenty thousand subshells, and
    # `min downloads --dry-run` sat there for half a minute before printing
    # anything. Deciding once per item and counting the answers is the same
    # output in under a second.
    local sorted kind n item total=0
    sorted=$(
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            nimo_bucket_set "$item"
            printf '%s\t%s\n' "$NIMO_BUCKET" "$item"
        done <<EOF
$items
EOF
    )

    while IFS= read -r kind; do
        [ -n "$kind" ] || continue
        n=$(printf '%s\n' "$sorted" | awk -F'\t' -v k="$kind" '$1 == k' | grep -c . 2>/dev/null)
        case "${n:-}" in ''|*[!0-9]*) n=0 ;; esac
        if [ "$n" -gt 0 ]; then
            nimo_row "$kind" "$(nimo_plural "$n" item)" ""
            total=$((total + n))
        fi
    done <<EOF
$(nimo_buckets_in "$sorted")
EOF

    nimo_blank
    nimo_rule
    nimo_total "In there" "$(nimo_plural "$total" item)"

    local arriving odd
    arriving=$(nimo_arriving_count "$src")
    if [ "$arriving" -gt 0 ]; then
        nimo_blank
        nimo_dim "$(nimo_plural "$arriving" file) still downloading — left alone"
    fi
    odd=$(nimo_unnameable_count "$src")
    if [ "$odd" -gt 0 ]; then
        [ "$arriving" -gt 0 ] || nimo_blank
        if [ "$odd" = "1" ]; then
            nimo_dim "1 file has a newline or a tab in its name"
            nimo_dim "nimo cannot write that down, so it leaves it alone"
        else
            nimo_dim "$odd files have a newline or a tab in their names"
            nimo_dim "nimo cannot write those down, so it leaves them alone"
        fi
    fi
    nimo_panel_close

    nimo_blank
    nimo_dim "everything moves into  ${root#$HOME/}/<${NIMO_BY:-kind}>/"
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

    # `sorted` already holds each item's bucket, worked out once above.
    local moved=0 failed=0 dest target done_so_far=0
    while IFS=$'\t' read -r kind item; do
        [ -n "${item:-}" ] || continue
        done_so_far=$((done_so_far + 1))
        [ "$total" -gt 40 ] && nimo_progress "moving $done_so_far of $total …"
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
$sorted
EOF
    nimo_progress_done

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
    local desk
    desk=$(nimo_desktop_dir)
    nimo_sort_folder "$desk" "your desktop" \
        "$desk/$NIMO_TIDY_DIR_NAME" desktop
}

nimo_cmd_downloads() {
    if [ "${NIMO_UNDO:-0}" = "1" ]; then
        nimo_sort_undo downloads
        return 0
    fi
    nimo_header
    local down
    down=$(nimo_downloads_dir)
    nimo_sort_folder "$down" "your downloads" \
        "$down/$NIMO_TIDY_DIR_NAME" downloads
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
    for where in "$(nimo_desktop_dir)" "$(nimo_downloads_dir)" "$HOME/Documents"; do
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

# What each of these would find, cheaply enough to show in a menu.
# Where `min screenshots` looks, and nowhere else. The menu used to count
# ~/Desktop while the command itself read OneDrive's — so on any signed-in
# Windows, and on any Mac with a synced desktop, the menu said "0 loose" and
# the command then found five.
nimo_count_loose_screenshots() {
    local where item n=0
    for where in "$(nimo_desktop_dir)" "$(nimo_downloads_dir)" "$HOME/Documents"; do
        [ -d "$where" ] || continue
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            [ "$(nimo_kind_of "$item")" = "Screenshots" ] && n=$((n + 1))
        done <<EOF
$(nimo_folder_items "$where")
EOF
    done
    printf '%s' "$n"
}

nimo_count_sortable() {
    nimo_line_count "$(nimo_folder_items "$1")"
}
