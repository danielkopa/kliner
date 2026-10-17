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

# A log that has been replayed is not a thing nimo can still put back, and
# offering it again is offering to undo something twice. It is moved aside
# rather than deleted — nimo does not delete — so the record of what happened
# is still there in ~/.nimo/undo/done.
nimo_undo_spend() {
    local log="$1" dest
    [ -f "$log" ] || return 0
    mkdir -p "$NIMO_UNDO_DIR/done" 2>/dev/null || return 0
    dest=$(nimo_free_name "$NIMO_UNDO_DIR/done" "$(basename "$log")")
    mv "$log" "$dest" 2>/dev/null || true
}

# What one preferences log changed, in the words the list uses. Most of them
# are `min setup`, a dozen settings at once, and "changed preferences" is the
# truth about those. The rest say which: `min zen` (and \ in an older Kliner)
# wrote a log for every press, and seventy lines of "changed preferences" in
# a row tell you nothing about any of them. The log holds what each setting
# was before, so which way it went is read off it, not guessed: a desktop
# switch that was off (or never set) and was written is icons that went.
#   $1  the log    $2  "one" for the singular the newest-change line uses
nimo_setup_says() {
    local f="$1" domain key state type prior n=0 icons=0 hid=0 dock=0
    while IFS=$'\t' read -r domain key state type prior; do
        [ -n "${domain:-}" ] || continue
        n=$((n + 1))
        case "$domain $key" in
            "com.apple.WindowManager HideDesktop"|"com.apple.WindowManager StandardHideDesktopIcons")
                icons=$((icons + 1))
                case "$state:${prior:-}" in had:1|had:true|had:yes) ;; *) hid=$((hid + 1)) ;; esac ;;
            "com.apple.finder CreateDesktop")
                icons=$((icons + 1))
                case "$state:${prior:-}" in had:0|had:false|had:no) ;; *) hid=$((hid + 1)) ;; esac ;;
            "com.apple.dock "*)
                dock=$((dock + 1)) ;;
        esac
    done < "$f"
    if [ "$n" -gt 0 ] && [ "$icons" -eq "$n" ]; then
        if [ "$hid" -eq "$n" ]; then printf 'hid desktop icons'
        elif [ "$hid" -eq 0 ]; then printf 'showed desktop icons'
        else printf 'changed desktop icons'
        fi
    elif [ "$n" -gt 0 ] && [ "$dock" -eq "$n" ]; then
        printf 'changed the dock'
    elif [ "${2:-}" = "one" ]; then
        printf 'changed a preference'
    else
        printf 'changed preferences'
    fi
}

# 20260826-162929 -> 26 Aug 16:29
# The newest thing nimo has done, in one line, for the page that opens on
# what it has been up to. Empty when it has done nothing.
#
#   "cleared your desktop, 05.09.2026 16:41"
nimo_undo_last() {
    local f name kind label stamp
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$f" ] || continue
        name=$(basename "$f")
        case "$name" in
            desktop-*)     label="cleared your desktop" ;;
            downloads-*)   label="sorted your downloads" ;;
            screenshots-*) label="gathered your screenshots" ;;
            blank-*)       label="emptied a file" ;;
            rename-*)      label="renamed a file" ;;
            startup-*)     label="stopped things starting" ;;
            dock-*)        label="rebuilt your dock" ;;
            setup-*)       label=$(nimo_setup_says "$f" one) ;;
            wallpaper.txt) label="changed your wallpaper" ;;
            *) continue ;;
        esac
        # A log opened and never written to is nothing to put back.
        case "$name" in
            wallpaper.txt) ;;
            *) [ "$(nimo_file_lines "$f")" -gt 0 ] || continue ;;
        esac
        stamp=$(printf '%s' "$name" | sed -e 's/^[a-z]*-//' -e 's/\.[a-z]*$//')
        kind=$(nimo_undo_when "$stamp")
        if [ -n "$kind" ]; then
            printf '%s, %s' "$label" "$kind"
        else
            printf '%s' "$label"
        fi
        return 0
    done <<EOF
$(ls -1t "$NIMO_UNDO_DIR"/*.tsv "$NIMO_BACKUP_DIR"/dock-*.plist \
         "$NIMO_BACKUP_DIR"/setup-*.tsv "$NIMO_BACKUP_DIR"/wallpaper.txt 2>/dev/null)
EOF
    return 1
}

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
            rename-*)      kind=rename;  label="renamed a file" ;;
            startup-*)     kind=startup; label="stopped things starting" ;;
            dock-*)        kind=dock;    label="rebuilt your dock" ;;
            setup-*)       kind=setup;   label=$(nimo_setup_says "$f") ;;
            wallpaper.txt) kind=wallpaper; label="changed your wallpaper" ;;
            *) continue ;;
        esac

        # A command that opened a log and then wrote nothing to it leaves an
        # empty file behind, and offering that as something to reverse is
        # offering to put nothing back.
        case "$kind" in
            desktop|setup|blank|rename|startup)
                [ "$(nimo_file_lines "$f")" -gt 0 ] || continue ;;
        esac

        stamp=$(printf '%s' "$name" | sed -e 's/^[a-z]*-//' -e 's/\.[a-z]*$//')
        when=$(nimo_undo_when "$stamp")

        case "$kind" in
            desktop) lines="$(nimo_plural "$(nimo_file_lines "$f")" file)" ;;
            setup)   lines="$(nimo_plural "$(nimo_file_lines "$f")" setting)" ;;
            blank)   lines="$(basename "$(cut -f1 "$f" 2>/dev/null | head -1)")" ;;
            rename)  lines="back to $(basename "$(cut -f1 "$f" 2>/dev/null | head -1)")" ;;
            startup) lines="$(nimo_plural "$(($(nimo_file_lines "$f") - 1))" thing)" ;;
            wallpaper) lines="back to $(nimo_wall_pretty "$(cat "$f" 2>/dev/null)")"; when="" ;;
            *)       lines="" ;;
        esac

        # Two spaces between the columns, for the same reason nimo_fact has
        # them: anything reading this back splits on two or more, and %-22s
        # only holds that apart while the label is short enough to be padded.
        labels="$labels$(printf '%-22s  %-18s  %s' "$label" "$when" "$lines")
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

    # Everything, in one go.
    #
    # `min tidy` is six commands, so putting it back was six commands, in the
    # right order, and knowing which. Newest first, because a later change can
    # sit on top of an earlier one and undoing the earlier one first would put
    # the later one back on top of it.
    if [ "${NIMO_ALL:-0}" = "1" ]; then
        nimo_dim "$(nimo_plural "$count" thing) to put back, newest first"
        nimo_panel_close
        nimo_blank

        if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
            local i=1
            while IFS= read -r label; do
                [ -n "$label" ] || continue
                printf '%s%s%2d%s  %s\n' "$NIMO_PAD" "$NIMO_C_DIM" "$i" "$NIMO_C_RESET" "$label"
                i=$((i + 1))
            done <<EOF
$labels
EOF
            nimo_blank
            nimo_dim "preview only, nothing was put back"
            nimo_blank
            return 0
        fi

        if ! nimo_confirm "Reverse $(nimo_plural "$count" thing)?"; then
            nimo_blank
            nimo_dim "nothing was changed"
            nimo_blank
            return 0
        fi

        local done_n=0 action kind file
        NIMO_UNDO_QUIET=1
        while IFS= read -r action; do
            [ -n "$action" ] || continue
            kind="${action%%	*}"
            file="${action#*	}"
            [ -n "$kind" ] && [ -n "$file" ] || continue
            case "$kind" in
                desktop)   nimo_sort_undo any "$file" >/dev/null 2>&1 ;;
                dock)      nimo_dock_restore "$file" >/dev/null 2>&1 ;;
                setup)     nimo_setup_restore "$file" >/dev/null 2>&1 ;;
                blank)     nimo_blank_undo "$file" >/dev/null 2>&1 ;;
                rename)    nimo_rename_undo "$file" >/dev/null 2>&1 ;;
                startup)   nimo_startup_undo "$file" >/dev/null 2>&1 ;;
                wallpaper) nimo_wall_restore >/dev/null 2>&1 ;;
            esac
            [ "$kind" = "wallpaper" ] || nimo_undo_spend "$file"
            done_n=$((done_n + 1))
        done <<EOF
$actions
EOF
        NIMO_UNDO_QUIET=0
        # a nested panel put NIMO_PAD back to the outer two spaces
        NIMO_PAD="  "

        nimo_blank
        nimo_ok "$(nimo_plural "$done_n" thing) put back"
        nimo_dim "your computer is where it was before nimo started"
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
        rename)    nimo_rename_undo "$file" ;;
        startup)   nimo_startup_undo "$file" ;;
        wallpaper) nimo_wall_restore ;;
    esac
    NIMO_UNDO_QUIET=0
    [ "$kind" = "wallpaper" ] || nimo_undo_spend "$file"
    return 0
}
