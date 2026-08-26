#!/usr/bin/env bash
# nimo :: lib/tools.sh — min top, min doctor, min update.

# ---- min top -------------------------------------------------------------

nimo_cmd_top() {
    nimo_banner
    nimo_title "Biggest folders in your home"

    local limit="${NIMO_LIMIT:-15}" list max total
    nimo_progress "measuring $HOME …"
    list=$(du -k -d 1 "$HOME" 2>/dev/null \
        | awk -v h="$HOME" -F'\t' '$2 != h && $2 != h"/"' \
        | sort -rn \
        | head -n "$limit")
    total=$(nimo_children_kb "$HOME")
    nimo_progress_done

    if [ -z "$list" ]; then
        nimo_dim "nothing to measure"
        nimo_blank
        return 0
    fi

    max=$(printf '%s\n' "$list" | head -1 | awk '{print $1 + 0}')

    printf '%s\n' "$list" | while IFS=$'\t' read -r kb path; do
        [ -n "${path:-}" ] || continue
        printf '  %-24s %10s  %s\n' \
            "$(basename "$path")" \
            "$(nimo_human_kb "$kb")" \
            "$(nimo_meter "$kb" "$max" 16)"
    done

    nimo_blank
    nimo_rule
    nimo_total "Everything in your home" "$(nimo_human_kb "$total")"
    nimo_blank
    nimo_dim "this is only a measurement — nothing here is deleted or changed"
    nimo_dim "to see what is actually safe to remove:  min preview"
    nimo_blank
}

# ---- min doctor ----------------------------------------------------------

nimo_os_line() {
    if nimo_is_macos && nimo_have sw_vers; then
        printf '%s %s (%s)' \
            "$(sw_vers -productName 2>/dev/null)" \
            "$(sw_vers -productVersion 2>/dev/null)" \
            "$(uname -m)"
    else
        printf '%s %s (%s)' "$(uname -s)" "$(uname -r)" "$(uname -m)"
    fi
}

nimo_uptime_line() {
    local raw
    raw=$(uptime 2>/dev/null) || { printf 'unknown'; return 0; }
    printf '%s' "$raw" | sed -e 's/.*up[ ]*//' -e 's/,[ ]*[0-9]* user.*//' -e 's/[ ]*$//'
}

nimo_cmd_doctor() {
    nimo_banner
    nimo_title "How your computer is doing"

    nimo_fact "System" "$(nimo_os_line)"
    nimo_fact "Uptime" "$(nimo_uptime_line)"

    local free total used
    free=$(nimo_disk_free_kb)
    total=$(nimo_disk_total_kb)
    used=$((total - free))
    if [ "$total" -gt 0 ]; then
        nimo_fact "Disk" \
            "$(printf '%s free of %s' "$(nimo_human_kb "$free")" "$(nimo_human_kb "$total")")" \
            "$(nimo_bar "$used" "$total" 16)"
    fi

    nimo_blank
    nimo_fact "Desktop" "$(nimo_plural "$(nimo_count_dir_items "$HOME/Desktop")" item)"
    nimo_fact "Downloads" "$(nimo_plural "$(nimo_count_dir_items "$HOME/Downloads")" item)"
    if nimo_is_macos; then
        nimo_fact "Trash" "$(nimo_plural "$(nimo_count_dir_items "$HOME/.Trash")" item)"
    else
        nimo_fact "Trash" "$(nimo_plural "$(nimo_count_dir_items "$HOME/.local/share/Trash/files")" item)"
    fi

    nimo_blank
    nimo_progress "adding up what could be freed …"
    nimo_register_targets
    nimo_scan
    local i safe_kb=0
    i=0
    while [ "$i" -lt "$NIMO_T_N" ]; do
        [ "${NIMO_T_SAFETY[$i]}" = "safe" ] && safe_kb=$((safe_kb + ${NIMO_R_KB[$i]}))
        i=$((i + 1))
    done
    nimo_progress_done

    if [ "$safe_kb" -gt 0 ]; then
        nimo_fact "Junk" "$(nimo_human_kb "$safe_kb")" "→ min clean"
    else
        nimo_fact "Junk" "none worth mentioning"
    fi

    local where
    where=$(command -v min 2>/dev/null || true)
    if [ -n "$where" ]; then
        nimo_fact "nimo" "v$NIMO_VERSION" "$where"
    else
        nimo_fact "nimo" "v$NIMO_VERSION" "not on your PATH — run ./install.sh"
    fi

    nimo_blank
}

# ---- min update ----------------------------------------------------------

nimo_cmd_update() {
    nimo_banner
    nimo_title "Update"

    if [ ! -d "$NIMO_ROOT/.git" ]; then
        nimo_warn "this copy of nimo is not a git repository"
        nimo_dim "$NIMO_ROOT"
        nimo_blank
        return 1
    fi

    if ! nimo_have git; then
        nimo_warn "git is not installed"
        nimo_blank
        return 1
    fi

    nimo_dim "pulling in $NIMO_ROOT …"
    nimo_blank
    if (cd "$NIMO_ROOT" && git pull --ff-only); then
        nimo_blank
        nimo_ok "nimo is up to date"
    else
        nimo_blank
        nimo_warn "could not update automatically"
        nimo_dim "try it by hand:  cd $NIMO_ROOT && git pull"
    fi
    nimo_blank
}
