#!/usr/bin/env bash
# nimo :: lib/undo.sh — everything nimo has ever done, and a way back.
#
# One list. Pick a line, and that change is reversed. This is the reason
# nimo is allowed to touch anything at all.

# How many lines are in this log.
#
# `grep -c .` prints 0 and exits 1 on an empty file, so the obvious
# `$(grep -c . "$f" || echo 0)` produces "0" and then a second "0" — a count
# with a newline in the middle of it. That went straight into the label, which
# then took two rows in the list, and the numbers you were being asked to pick
# from no longer lined up with the things they named.
nimo_file_lines() {
    local n
    n=$(grep -c . "$1" 2>/dev/null)
    case "${n:-}" in
        ''|*[!0-9]*) printf '0' ;;
        *)           printf '%s' "$n" ;;
    esac
}

# 20260826-162929 -> 26 Aug 16:29
nimo_undo_when() {
    printf '%s' "$1" | sed -n 's/^\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\).*/\3.\2.\1 \4:\5/p'
}

nimo_cmd_undo() {
    nimo_header
    nimo_panel_open "what nimo has done"

    local labels="" actions="" f stamp when lines name kind label

    # Everything nimo can reverse, newest first — across kinds, not within
    # them. Grouping by kind first meant the newest thing you did was rarely
    # the first thing offered, which is the one thing this list is for.
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$f" ] || continue
        name=$(basename "$f")
        kind=""
        case "$name" in
            desktop-*)     kind=desktop; label="cleared your desktop" ;;
            downloads-*)   kind=desktop; label="sorted your downloads" ;;
            screenshots-*) kind=desktop; label="gathered screenshots" ;;
            blank-*)       kind=blank;   label="emptied a file" ;;
            startup-*)     kind=startup; label="stopped things starting" ;;
            dock-*)        kind=dock;    label="rebuilt your dock" ;;
            setup-*)       kind=setup;   label="changed preferences" ;;
            wallpaper.txt) kind=wallpaper; label="changed your wallpaper" ;;
            *) continue ;;
        esac

        # A command that opened a log and then wrote nothing to it leaves an
        # empty file behind, and offering that as something to reverse is
        # offering to put nothing back.
        case "$kind" in
            desktop|setup|blank|startup)
                [ "$(nimo_file_lines "$f")" -gt 0 ] || continue ;;
        esac

        stamp=$(printf '%s' "$name" | sed -e 's/^[a-z]*-//' -e 's/\.[a-z]*$//')
        when=$(nimo_undo_when "$stamp")

        case "$kind" in
            desktop) lines="$(nimo_plural "$(nimo_file_lines "$f")" file)" ;;
            setup)   lines="$(nimo_plural "$(nimo_file_lines "$f")" setting)" ;;
            blank)   lines="$(basename "$(cut -f1 "$f" 2>/dev/null | head -1)")" ;;
            startup) lines="$(nimo_plural "$(($(nimo_file_lines "$f") - 1))" thing)" ;;
            wallpaper) lines="back to $(nimo_wall_pretty "$(cat "$f" 2>/dev/null)")"; when="" ;;
            *)       lines="" ;;
        esac

        labels="$labels$(printf '%-22s %-18s %s' "$label" "$when" "$lines")
"
        actions="${actions}${kind}	$f
"
    done <<EOF
$(ls -1t "$NIMO_UNDO_DIR"/*.tsv "$NIMO_BACKUP_DIR"/dock-*.plist \
         "$NIMO_BACKUP_DIR"/setup-*.tsv "$NIMO_BACKUP_DIR"/wallpaper.txt 2>/dev/null)
EOF

    local count
    count=$(nimo_line_count "$actions")

    if [ "$count" -eq 0 ]; then
        nimo_ok "nimo has not changed anything yet."
        nimo_panel_close
        nimo_blank
        return 0
    fi

    if [ "${NIMO_LIST:-0}" = "1" ] || [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        local i=1 label
        while IFS= read -r label; do
            [ -n "$label" ] || continue
            printf '%s%s%2d%s  %s\n' "$NIMO_PAD" "$NIMO_C_DIM" "$i" "$NIMO_C_RESET" "$label"
            i=$((i + 1))
        done <<EOF
$labels
EOF
        nimo_panel_close
        nimo_blank
        nimo_dim "run  min undo  to reverse one of these"
        nimo_blank
        return 0
    fi

    nimo_dim "pick the one to reverse. nothing else is touched."
    nimo_blank

    local choice=""
    if ! choice=$(nimo_pick single "↑↓ move   enter reverse   q cancel" "$labels") || [ -z "$choice" ]; then
        nimo_panel_close
        nimo_blank
        nimo_dim "nothing was changed"
        nimo_blank
        return 0
    fi
    nimo_panel_close

    local action kind file
    action=$(printf '%s\n' "$actions" | sed -n "${choice}p")
    kind="${action%%	*}"
    file="${action#*	}"

    if [ -z "$kind" ] || [ -z "$file" ]; then
        nimo_blank
        nimo_dim "nothing was changed"
        nimo_blank
        return 0
    fi

    nimo_blank
    NIMO_UNDO_QUIET=1
    case "$kind" in
        desktop)   nimo_sort_undo any "$file" ;;
        dock)      nimo_dock_restore "$file" ;;
        setup)     nimo_setup_restore "$file" ;;
        blank)     nimo_blank_undo "$file" ;;
        startup)   nimo_startup_undo "$file" ;;
        wallpaper) nimo_wall_restore ;;
    esac
    NIMO_UNDO_QUIET=0
    return 0
}
