#!/bin/sh
# cabextract-compatible wrapper over macOS's bsdtar (libarchive reads Microsoft CAB files, including
# self-extracting .exe). Supports the options winetricks uses: -q, -L, -d DIR, -F PATTERN, -v.
dir=.
lower=0
filter=
list=$(mktemp -t dormer-cab) || exit 1
trap 'rm -f "$list"; [ -n "$tmp" ] && rm -rf "$tmp"' EXIT
while [ $# -gt 0 ]; do
    case "$1" in
        -q|--quiet|-f|--fix) ;;
        -L|--lowercase) lower=1 ;;
        -v|--version) echo "cabextract (Dormer wrapper over bsdtar)"; exit 0 ;;
        -d) dir=$2; shift ;;
        -d?*) dir=${1#-d} ;;
        --directory=*) dir=${1#--directory=} ;;
        -F) filter=$2; shift ;;
        -F?*) filter=${1#-F} ;;
        --filter=*) filter=${1#--filter=} ;;
        --) shift; while [ $# -gt 0 ]; do printf '%s\n' "$1" >> "$list"; shift; done; break ;;
        -*) echo "cabextract: unsupported option: $1" >&2; exit 2 ;;
        *) printf '%s\n' "$1" >> "$list" ;;
    esac
    shift
done
[ -s "$list" ] || { echo "cabextract: no files given" >&2; exit 2; }
mkdir -p "$dir" || exit 1
lowercase() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
status=0
while IFS= read -r archive; do
    tmp=$(mktemp -d -t dormer-cab) || exit 1
    if [ -n "$filter" ]; then
        names=$(mktemp -t dormer-cab-names) || exit 1
        pattern=$(lowercase "$filter")
        tar -tf "$archive" 2>/dev/null | while IFS= read -r member; do
            lname=$(lowercase "$member")
            # shellcheck disable=SC2254
            case "$lname" in $pattern) printf '%s\n' "$member" ;; esac
        done > "$names"
        if [ -s "$names" ]; then tar -xf "$archive" -C "$tmp" -T "$names" 2>/dev/null || status=1; fi
        rm -f "$names"
    else
        tar -xf "$archive" -C "$tmp" 2>/dev/null || status=1
    fi
    if [ "$lower" = 1 ]; then
        find "$tmp" -depth -mindepth 1 | while IFS= read -r path; do
            base=$(basename "$path"); lbase=$(lowercase "$base")
            [ "$base" = "$lbase" ] || mv "$path" "$(dirname "$path")/$lbase"
        done
    fi
    cp -R "$tmp"/. "$dir"/ || status=1
    rm -rf "$tmp"; tmp=
done < "$list"
exit $status
