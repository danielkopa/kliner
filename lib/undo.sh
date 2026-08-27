#!/usr/bin/env bash
# nimo :: lib/undo.sh — everything nimo has ever done, and a way back.
#
# One list. Pick a line, and that change is reversed. This is the reason
# nimo is allowed to touch anything at all.

# 20260826-162929 -> 26 Aug 16:29
nimo_undo_when() {
    printf '%s' "$1" | sed -n 's/^\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\).*/\3.\2.\1 \4:\5/p'
}

nimo_cmd_undo() {
    nimo_header
    nimo_panel_open "what nimo has done"

    local labels="" actions="" f stamp when lines

    # newest first, by modification time — see nimo_newest in core.sh
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$f" ] || continue
        stamp=$(basename "$f" | sed -e 's/^desktop-//' -e 's/\.tsv$//')
        when=$(nimo_undo_when "$stamp")
        lines=$(grep -c . "$f" 2>/dev/null || true)
        labels="$labels$(printf '%-22s %-18s %s' "cleared your desktop" "$when" "$(nimo_plural "${lines:-0}" file)")
"
        actions="${actions}desktop	$f
"
    done <<EOF
$(ls -1t "$NIMO_UNDO_DIR"/desktop-*.tsv 2>/dev/null)
EOF

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$f" ] || continue
        stamp=$(basename "$f" | sed -e 's/^dock-//' -e 's/\.plist$//')
        when=$(nimo_undo_when "$stamp")
        labels="$labels$(printf '%-22s %-18s %s' "rebuilt your dock" "$when" "")
"
        actions="${actions}dock	$f
"
    done <<EOF
$(ls -1t "$NIMO_BACKUP_DIR"/dock-*.plist 2>/dev/null)
EOF

    # preference changes
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$f" ] || continue
        stamp=$(basename "$f" | sed -e 's/^setup-//' -e 's/\.tsv$//')
        when=$(nimo_undo_when "$stamp")
        lines=$(grep -c . "$f" 2>/dev/null || true)
        labels="$labels$(printf '%-22s %-18s %s' "changed preferences" "$when" "$(nimo_plural "${lines:-0}" setting)")
"
        actions="${actions}setup	$f
"
    done <<EOF
$(ls -1t "$NIMO_BACKUP_DIR"/setup-*.tsv 2>/dev/null)
EOF

    # the wallpaper nimo replaced
    f="$NIMO_BACKUP_DIR/wallpaper.txt"
    if [ -f "$f" ]; then
        when=$(cat "$f" 2>/dev/null)
        labels="$labels$(printf '%-22s %-18s %s' "changed your wallpaper" "" "back to $(nimo_wall_pretty "${when:-unknown}")")
"
        actions="${actions}wallpaper	$f
"
    fi

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
        desktop)   nimo_desktop_undo "$file" ;;
        dock)      nimo_dock_restore "$file" ;;
        setup)     nimo_setup_restore "$file" ;;
        wallpaper) nimo_wall_restore ;;
    esac
    NIMO_UNDO_QUIET=0
    return 0
}
