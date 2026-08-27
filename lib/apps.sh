#!/usr/bin/env bash
# nimo :: lib/apps.sh — what you installed once and never opened again,
# and the bin you keep meaning to take out.

# YYYY-MM-DD, this many days ago. BSD date first, GNU second.
nimo_days_ago() {
    local n="${1:-180}"
    date -v-"${n}"d +%Y-%m-%d 2>/dev/null && return 0
    date -d "$n days ago" +%Y-%m-%d 2>/dev/null && return 0
    printf ''
}

# When was this app last opened? Empty when macOS never noticed.
nimo_app_last_used() {
    local raw
    raw=$(mdls -name kMDItemLastUsedDate -raw "$1" 2>/dev/null) || return 1
    case "$raw" in
        ''|'(null)') return 1 ;;
    esac
    printf '%s' "${raw%% *}"
}

# Where apps live. A function so the tests can point it somewhere harmless.
nimo_app_dirs() {
    printf '%s\n' "/Applications" "$HOME/Applications"
}

nimo_cmd_apps() {
    nimo_header

    if ! nimo_is_macos; then
        nimo_warn "reading when an app was last opened is a macOS thing"
        nimo_blank
        return 0
    fi

    if ! nimo_have mdls; then
        nimo_warn "nimo needs mdls for this, and cannot find it"
        nimo_blank
        return 1
    fi

    local days="${NIMO_DAYS:-30}"
    [ "$days" -lt 90 ] && days=180
    local cutoff
    cutoff=$(nimo_days_ago "$days")

    if [ -z "$cutoff" ]; then
        nimo_warn "nimo could not work out what $days days ago was"
        nimo_blank
        return 1
    fi

    nimo_progress "asking macOS when you last opened things …"

    local found="" app last kb dir
    while IFS= read -r dir; do
        [ -d "$dir" ] || continue
        for app in "$dir"/*.app; do
        [ -d "$app" ] || continue
        last=$(nimo_app_last_used "$app") || last=""
        [ -n "$last" ] || continue
        [ "$last" \< "$cutoff" ] || continue
        kb=$(nimo_path_kb "$app")
        found="$found$kb	$last	$app
"
        done
    done <<EOF
$(nimo_app_dirs)
EOF
    nimo_progress_done

    local count total=0
    count=$(nimo_line_count "$found")

    nimo_panel_open "not opened since $cutoff"

    if [ "$count" -eq 0 ]; then
        nimo_ok "Everything here has been used lately."
        nimo_panel_close
        nimo_blank
        return 0
    fi

    local shown=0 name
    while IFS=$'\t' read -r kb last app; do
        [ -n "${app:-}" ] || continue
        total=$((total + kb))
        shown=$((shown + 1))
        [ "$shown" -gt "${NIMO_LIMIT:-15}" ] && continue
        name=$(basename "$app")
        nimo_row_kb "${name%.app}" "$kb" "last opened $last"
    done <<EOF
$(printf '%s' "$found" | sort -rn)
EOF

    [ "$count" -gt "${NIMO_LIMIT:-15}" ] && nimo_dim "… and $((count - ${NIMO_LIMIT:-15})) more"

    nimo_blank
    nimo_rule
    nimo_total "$(nimo_plural "$count" app)" "$(nimo_human_kb "$total")"
    nimo_panel_close
    nimo_dim "nimo does not uninstall anything — this is a list, not a plan"
    nimo_dim "drag the ones you agree with to the Trash, then  min empty"
    nimo_blank
    return 0
}

# ---- min empty -----------------------------------------------------------

nimo_trash_dir() {
    case "$(nimo_platform)" in
        macos)   printf '%s' "$HOME/.Trash" ;;
        windows) printf '' ;;
        *)       printf '%s' "$HOME/.local/share/Trash/files" ;;
    esac
}

nimo_cmd_empty() {
    nimo_header

    local trash kb count
    trash=$(nimo_trash_dir)

    # The Recycle Bin is not a folder of files — it is files plus an index,
    # and deleting one without the other leaves Windows confused about what it
    # still holds. Emptying it is one right-click away and nimo does not
    # improve on that.
    if [ -z "$trash" ]; then
        nimo_warn "emptying the Recycle Bin is Windows' own job"
        nimo_dim "right-click it, or run:  Clear-RecycleBin"
        nimo_blank
        return 0
    fi
    kb=$(nimo_children_kb "$trash")
    count=$(nimo_count_children "$trash")

    nimo_panel_open "the trash"

    if [ "${count:-0}" -eq 0 ]; then
        nimo_ok "Already empty."
        nimo_panel_close
        nimo_blank
        return 0
    fi

    nimo_row_kb "$(nimo_plural "$count" item)" "$kb" "waiting to be taken out"
    nimo_panel_close
    nimo_blank
    nimo_dim "this one is not undoable — the Trash is already the undo"
    nimo_blank

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "preview only — nothing was emptied"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "Empty the trash, $(nimo_human_kb "$kb")?"; then
        nimo_blank
        nimo_dim "still there"
        nimo_blank
        return 0
    fi

    nimo_purge_children "$trash"

    local left
    left=$(nimo_children_kb "$trash")
    nimo_blank
    nimo_ok "Freed $(nimo_human_kb "$((kb - left))")"
    [ "$(nimo_count_children "$trash")" -gt 0 ] && \
        nimo_dim "some items were in use and stayed"
    nimo_blank
    return 0
}
