#!/usr/bin/env bash
# nimo :: lib/clean.sh — scan, report, and (only if you say so) clean.

nimo_report() {
    local i n kb count safe_kb=0 review_kb=0 shown=0
    n=$NIMO_T_N

    if [ -n "${NIMO_ONLY:-}" ]; then
        nimo_panel_open "safe to clean · only ${NIMO_ONLY}"
    else
        nimo_panel_open "safe to clean"
    fi
    i=0
    while [ "$i" -lt "$n" ]; do
        if [ "${NIMO_T_SAFETY[$i]}" = "safe" ] && nimo_selected "$i"; then
            kb="${NIMO_R_KB[$i]}"; count="${NIMO_R_COUNT[$i]}"
            if [ "$kb" -gt 0 ]; then
                nimo_row_kb "${NIMO_T_LABEL[$i]}" "$kb" "${NIMO_T_NOTE[$i]}"
                safe_kb=$((safe_kb + kb))
                shown=1
            fi
        fi
        i=$((i + 1))
    done
    [ "$shown" = "0" ] && nimo_dim "nothing to clean here"
    nimo_blank
    nimo_rule
    nimo_total "Total" "$(nimo_human_kb "$safe_kb")"
    nimo_disk_line
    nimo_panel_close

    shown=0
    nimo_panel_open "worth a look"
    nimo_dim "nimo never deletes anything in this section"
    nimo_blank
    i=0
    while [ "$i" -lt "$n" ]; do
        if [ "${NIMO_T_SAFETY[$i]}" = "review" ] && nimo_selected "$i"; then
            kb="${NIMO_R_KB[$i]}"; count="${NIMO_R_COUNT[$i]}"
            if [ "$kb" -gt 0 ]; then
                nimo_row_kb "${NIMO_T_LABEL[$i]}" "$kb" "$(nimo_plural "$count" item) · ${NIMO_T_NOTE[$i]}"
                review_kb=$((review_kb + kb))
                shown=1
            fi
        fi
        i=$((i + 1))
    done
    [ "$shown" = "0" ] && nimo_dim "nothing here that needs a second look"
    nimo_panel_close

    NIMO_SAFE_KB="$safe_kb"
    NIMO_REVIEW_KB="$review_kb"
}

nimo_clean_target() {
    local i="$1" p
    local kind="${NIMO_T_KIND[$1]}"
    case "$kind" in
        contents)
            while IFS= read -r p; do
                [ -n "$p" ] || continue
                nimo_purge_children "$p"
            done <<EOF
$(nimo_target_paths "$i")
EOF
            ;;
        tree)
            while IFS= read -r p; do
                [ -n "$p" ] || continue
                nimo_purge_path "$p"
            done <<EOF
$(nimo_target_paths "$i")
EOF
            ;;
        *)
            return 0 ;;
    esac
}

nimo_do_clean() {
    local i n before after freed=0 result
    n=$NIMO_T_N
    i=0
    while [ "$i" -lt "$n" ]; do
        if [ "${NIMO_T_SAFETY[$i]}" = "safe" ] && nimo_selected "$i" && [ "${NIMO_R_KB[$i]}" -gt 0 ]; then
            before="${NIMO_R_KB[$i]}"
            nimo_progress "cleaning  ${NIMO_T_LABEL[$i]} …"
            nimo_clean_target "$i"
            result=$(nimo_measure "$i")
            after="${result%% *}"
            freed=$((freed + before - after))
        fi
        i=$((i + 1))
    done
    nimo_progress_done
    NIMO_FREED_KB="$freed"
}

# Machine readable output for --json. Sizes are in bytes.
nimo_json_report() {
    local i=0 safe_kb=0 review_kb=0 first=1
    printf '{\n'
    printf '  "nimo": "%s",\n' "$NIMO_VERSION"
    printf '  "disk": { "free_bytes": %s, "total_bytes": %s },\n' \
        "$(nimo_kb_to_bytes "$(nimo_disk_free_kb)")" \
        "$(nimo_kb_to_bytes "$(nimo_disk_total_kb)")"
    printf '  "targets": [\n'
    while [ "$i" -lt "$NIMO_T_N" ]; do
        if nimo_selected "$i"; then
            [ "$first" = "1" ] || printf ',\n'
            first=0
            printf '    { "id": "%s", "label": "%s", "safety": "%s", "bytes": %s, "items": %s }' \
                "${NIMO_T_ID[$i]}" "${NIMO_T_LABEL[$i]}" "${NIMO_T_SAFETY[$i]}" \
                "$(nimo_kb_to_bytes "${NIMO_R_KB[$i]}")" "${NIMO_R_COUNT[$i]}"
            if [ "${NIMO_T_SAFETY[$i]}" = "safe" ]; then
                safe_kb=$((safe_kb + ${NIMO_R_KB[$i]}))
            else
                review_kb=$((review_kb + ${NIMO_R_KB[$i]}))
            fi
        fi
        i=$((i + 1))
    done
    printf '\n  ],\n'
    printf '  "safe_bytes": %s,\n' "$(nimo_kb_to_bytes "$safe_kb")"
    printf '  "review_bytes": %s,\n' "$(nimo_kb_to_bytes "$review_kb")"
    printf '  "freed_bytes": %s\n' "$(nimo_kb_to_bytes "${NIMO_FREED_KB:-0}")"
    printf '}\n'
}

nimo_cmd_clean() {
    if [ "${NIMO_JSON:-0}" = "1" ]; then
        NIMO_QUIET=1
        nimo_register_targets
        nimo_scan
        if [ "${NIMO_DRY_RUN:-0}" != "1" ] && [ "${NIMO_ASSUME_YES:-0}" = "1" ]; then
            nimo_do_clean
            nimo_scan
        fi
        nimo_json_report
        return 0
    fi

    nimo_header
    nimo_register_targets

    nimo_dim "looking around your computer …"
    nimo_scan
    nimo_report
    nimo_blank

    if [ "${NIMO_SAFE_KB:-0}" -le 0 ]; then
        nimo_ok "Nothing to clean. Your computer is already tidy."
        nimo_blank
        return 0
    fi

    if [ "${NIMO_DRY_RUN:-0}" = "1" ]; then
        nimo_blank
        nimo_dim "preview only — nothing was deleted"
        nimo_dim "run  min clean  when you want nimo to actually free this up"
        nimo_blank
        return 0
    fi

    nimo_blank
    if ! nimo_confirm "Free up $(nimo_human_kb "$NIMO_SAFE_KB")?"; then
        nimo_blank
        nimo_dim "nothing was deleted"
        nimo_blank
        return 0
    fi

    nimo_blank
    nimo_do_clean
    nimo_ok "Freed $(nimo_human_kb "${NIMO_FREED_KB:-0}")"
    nimo_disk_line
    nimo_blank
    nimo_dim "your computer feels a little better"
    if [ $(( ${NIMO_FREED_KB:-0} * 10 )) -lt $(( ${NIMO_SAFE_KB:-0} * 9 )) ]; then
        nimo_dim "some files were in use or protected by macOS and were left alone"
    fi
    nimo_blank
}

nimo_cmd_preview() {
    NIMO_DRY_RUN=1
    nimo_cmd_clean
}
