#!/usr/bin/env bash
# nimo :: lib/dupes.sh — the same file, kept four times.
#
# nimo only ever looks. It groups files by size first, because two files of
# different sizes cannot be the same file, and only then does it read the
# handful of candidates that are left. Nothing here deletes anything.

nimo_hash() {
    if nimo_have shasum; then
        shasum -a 1 "$1" 2>/dev/null | awk '{print $1}'
    elif nimo_have sha1sum; then
        sha1sum "$1" 2>/dev/null | awk '{print $1}'
    elif nimo_have md5; then
        md5 -q "$1" 2>/dev/null
    else
        cksum "$1" 2>/dev/null | awk '{print $1 "-" $2}'
    fi
}

nimo_bytes_of() {
    wc -c < "$1" 2>/dev/null | tr -d ' '
}

nimo_cmd_duplicates() {
    nimo_header

    local where="${NIMO_TARGET:-}" roots
    if [ -n "$where" ]; then
        roots="$HOME/$where"
        [ -d "$where" ] && roots="$where"
    else
        roots="$HOME/Desktop
$HOME/Downloads
$HOME/Documents"
    fi

    local work
    work=$(mktemp -d "${TMPDIR:-/tmp}/nimo-dupes.XXXXXX") || return 1

    nimo_progress "looking for copies …"

    local root file size
    while IFS= read -r root; do
        [ -n "$root" ] || continue
        [ -d "$root" ] || continue
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            size=$(nimo_bytes_of "$file")
            [ -n "$size" ] || continue
            [ "$size" -gt 0 ] 2>/dev/null || continue
            printf '%s\t%s\n' "$size" "$file" >> "$work/sizes"
        done <<EOF
$(find "$root" -maxdepth 4 -type f -size +64k 2>/dev/null | head -2000)
EOF
    done <<EOF
$roots
EOF

    # only sizes that turn up more than once are worth reading
    if [ -s "$work/sizes" ]; then
        sort -n "$work/sizes" | awk -F'\t' '
            { count[$1]++ }
            END { for (s in count) if (count[s] > 1) print s }
        ' > "$work/sizes-twice"
    fi

    : > "$work/hashes"
    if [ -s "${work}/sizes-twice" ]; then
        while IFS= read -r size; do
            [ -n "$size" ] || continue
            awk -F'\t' -v s="$size" '$1 == s {print $2}' "$work/sizes" \
                | while IFS= read -r file; do
                    [ -n "$file" ] || continue
                    printf '%s\t%s\t%s\n' "$(nimo_hash "$file")" "$size" "$file" >> "$work/hashes"
                done
        done < "$work/sizes-twice"
    fi

    nimo_progress_done

    local groups=0 wasted=0
    nimo_panel_open "the same file, more than once"

    if [ -s "$work/hashes" ]; then
        local hash size copies first home_rel
        while IFS= read -r hash; do
            [ -n "$hash" ] || continue
            copies=$(awk -F'\t' -v h="$hash" '$1 == h {print $3}' "$work/hashes")
            [ "$(nimo_line_count "$copies")" -gt 1 ] || continue
            size=$(awk -F'\t' -v h="$hash" '$1 == h {print $2; exit}' "$work/hashes")
            groups=$((groups + 1))
            wasted=$((wasted + (size / 1024) * ($(nimo_line_count "$copies") - 1)))

            first=1
            while IFS= read -r file; do
                [ -n "$file" ] || continue
                if [ "$first" = "1" ]; then
                    home_rel="${file%/*}"
                    nimo_row_kb "$(basename "$file")" "$((size / 1024))" "${home_rel#$HOME/}"
                    first=0
                else
                    home_rel="${file%/*}"
                    printf '%s%s  also in %s%s\n' "$NIMO_PAD" "$NIMO_C_DIM" "${home_rel#$HOME/}" "$NIMO_C_RESET"
                fi
            done <<EOF
$copies
EOF
            nimo_blank
            [ "$groups" -ge "${NIMO_LIMIT:-15}" ] && break
        done <<EOF
$(awk -F'\t' '{print $1}' "$work/hashes" | sort -u)
EOF
    fi

    rm -rf "$work" 2>/dev/null

    if [ "$groups" -eq 0 ]; then
        nimo_ok "No copies worth mentioning."
        nimo_panel_close
        nimo_blank
        return 0
    fi

    nimo_total "$(nimo_plural "$groups" file) with copies" "$(nimo_human_kb "$wasted")"
    nimo_panel_close
    nimo_dim "nimo does not delete these — it cannot know which copy you meant"
    nimo_blank
    return 0
}
