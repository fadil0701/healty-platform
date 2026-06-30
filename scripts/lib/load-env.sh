#!/usr/bin/env bash
# Baca file .env ke environment tanpa `source` (aman untuk spasi, (), !, @).
# Usage: source scripts/lib/load-env.sh && load_env_file .env

load_env_file() {
    local file="${1:?}"
    local line key val

    [[ -f "$file" ]] || {
        echo "ERROR: File .env tidak ditemukan: $file" >&2
        return 1
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line//$'\r'/}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        [[ "$line" != *"="* ]] && continue

        key="${line%%=*}"
        val="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"

        if [[ "$val" == \"*\" && "$val" == *\" ]]; then
            val="${val:1:${#val}-2}"
        elif [[ "$val" == \'*\' && "$val" == *\' ]]; then
            val="${val:1:${#val}-2}"
        fi

        export "${key}=${val}"
    done < "$file"
}
