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

# The same question on Windows, answered as honestly as Windows allows.
#
# There is no equivalent of kMDItemLastUsedDate: Windows does not record when
# you last opened a program. What it does record is when each one was
# installed and roughly how big it is, so that is what nimo shows — and it
# says which question it is actually answering rather than implying the other.
#
# Read only. This has never uninstalled anything and this does not start.
nimo_apps_windows() {
    if ! nimo_ps_ready; then
        nimo_warn "nimo needs PowerShell to read what is installed, and cannot find it"
        nimo_blank
        return 1
    fi

    local days="${NIMO_DAYS:-30}"
    [ "$days" -lt 90 ] && days=180
    local cutoff
    cutoff=$(nimo_days_ago "$days")
    cutoff=$(printf '%s' "$cutoff" | tr -d '-')

    nimo_progress "asking windows what is installed …"

    local raw found="" name when size
    raw=$(nimo_win_apps)
    while IFS=$'\t' read -r name when size; do
        [ -n "${name:-}" ] || continue
        when=$(printf '%s' "${when:-}" | tr -d ' \r')
        size=$(printf '%s' "${size:-0}" | tr -d ' \r')
        case "$size" in ''|*[!0-9]*) size=0 ;; esac
        case "$when" in
            ????????)
                # installed since the cutoff, so not what this list is for
                [ "$when" -lt "$cutoff" ] 2>/dev/null || continue ;;
            *) when="" ;;
        esac
        found="$found$size	$when	$name
"
    done <<EOF
$raw
EOF
    nimo_progress_done

    local count total=0
    count=$(nimo_line_count "$found")

    nimo_panel_open "installed a long time ago"

    if [ "$count" -eq 0 ]; then
        nimo_ok "Nothing here has been sitting around."
        nimo_panel_close
        nimo_blank
        return 0
    fi

    local shown=0 pretty
    while IFS=$'\t' read -r size when name; do
        [ -n "${name:-}" ] || continue
        total=$((total + size))
        shown=$((shown + 1))
        [ "$shown" -gt "${NIMO_LIMIT:-15}" ] && continue
        if [ -n "$when" ]; then
            pretty="installed $(printf '%s' "$when" | sed -e 's/\(....\)\(..\)\(..\)/\1-\2-\3/')"
        else
            pretty="windows did not record when"
        fi
        nimo_row_kb "$name" "$size" "$pretty"
    done <<EOF
$(printf '%s' "$found" | sort -rn)
EOF

    [ "$count" -gt "${NIMO_LIMIT:-15}" ] && nimo_dim "… and $((count - ${NIMO_LIMIT:-15})) more"

    nimo_blank
    nimo_rule
    nimo_total "$(nimo_plural "$count" program)" "$(nimo_human_kb "$total")"
    nimo_panel_close
    nimo_dim "windows does not record when you last opened a program, so this is"
    nimo_dim "by install date — nimo cannot tell you which ones you have forgotten"
    nimo_blank
    nimo_dim "nimo does not uninstall anything — this is a list, not a plan"
    nimo_dim "remove them from  Settings › Apps › Installed apps"
    nimo_blank
    return 0
}

nimo_cmd_apps() {
    nimo_header

    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_apps_windows
        return $?
    fi

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

# Windows has a Recycle Bin and no folder to point at, so "is there a trash
# here" and "where is it" stopped being the same question. Everything that
# used to test the path for emptiness asks these three instead.
nimo_has_trash() {
    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_ps_ready && return 0
        return 1
    fi
    [ -n "$(nimo_trash_dir)" ]
}

nimo_trash_count() {
    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_win_bin_count
        return 0
    fi
    nimo_count_children "$(nimo_trash_dir)"
}

nimo_trash_kb() {
    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_win_bin_kb
        return 0
    fi
    nimo_children_kb "$(nimo_trash_dir)"
}

nimo_trash_empty() {
    if [ "$(nimo_platform)" = "windows" ]; then
        nimo_win_bin_empty
        return 0
    fi
    nimo_purge_children "$(nimo_trash_dir)"
}

nimo_cmd_empty() {
    nimo_header

    local kb count what

    # The Recycle Bin is files plus an index, and deleting one without the
    # other leaves Windows confused about what it still holds. So nimo does
    # not reach into it — it asks Windows how much is in there, and asks
    # Windows to empty it. Same command, same question, same yes.
    if ! nimo_has_trash; then
        if [ "$(nimo_platform)" = "windows" ]; then
            nimo_warn "nimo needs PowerShell to reach the Recycle Bin, and cannot find it"
            nimo_dim "right-click the bin, or run:  Clear-RecycleBin"
        else
            nimo_warn "nimo cannot find a trash folder on this system"
        fi
        nimo_blank
        return 0
    fi

    what="the trash"
    [ "$(nimo_platform)" = "windows" ] && what="the recycle bin"

    nimo_progress "asking what is in there …"
    kb=$(nimo_trash_kb)
    count=$(nimo_trash_count)
    nimo_progress_done

    nimo_panel_open "$what"

    if [ "${count:-0}" -eq 0 ]; then
        nimo_ok "Already empty."
        nimo_panel_close
        nimo_blank
        return 0
    fi

    nimo_row_kb "$(nimo_plural "$count" item)" "$kb" "waiting to be taken out"
    nimo_panel_close
    nimo_blank
    nimo_dim "this one is not undoable — $what is already the undo"
    nimo_blank

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_dim "preview only — nothing was emptied"
        nimo_blank
        return 0
    fi

    if ! nimo_confirm "Empty $what, $(nimo_human_kb "$kb")?"; then
        nimo_blank
        nimo_dim "still there"
        nimo_blank
        return 0
    fi

    nimo_trash_empty

    local left
    left=$(nimo_trash_kb)
    nimo_blank
    nimo_ok "Freed $(nimo_human_kb "$((kb - left))")"
    [ "$(nimo_trash_count)" -gt 0 ] && \
        nimo_dim "some items were in use and stayed"
    nimo_blank
    return 0
}
