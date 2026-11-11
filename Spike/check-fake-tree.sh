#!/bin/sh
# Runs the spike against a fake home built by make-fake-tree.sh and compares its output with
# the numbers the tree was built to produce. POSIX sh; runs under sh, bash or zsh.
#
# Usage: sh Spike/check-fake-tree.sh <dir>
#
# Expected allocated sizes assume APFS with 4096-byte allocation blocks.

set -eu

if [ $# -ne 1 ]; then
    echo "usage: $0 <dir>" >&2
    exit 2
fi

home="$1"
if [ ! -d "$home/Library/CloudStorage" ]; then
    echo "error: $home does not look like a tree built by make-fake-tree.sh" >&2
    exit 2
fi
here="$(cd "$(dirname "$0")" && pwd)"
spike="$here/footprint-spike.swift"
work="$(mktemp -d -t cloudpane-check)"
cases="$work/cases"
cleanup() {
    # Only the fixed names this script creates below; nothing is removed recursively.
    chmod u+rwx "$cases/unlistable" 2>/dev/null || true
    rm -f "$cases/full/keep.txt" "$cases/unlistable/keep.txt" "$cases/a-file" \
          "$cases/link" "$cases/link-full"
    rmdir "$cases/full" "$cases/unlistable" "$cases/empty-target" 2>/dev/null || true
    rmdir "$cases" 2>/dev/null || true
    rm -f "$work"/*.md "$work"/*.expected "$work"/*.actual "$work"/*.raw "$work"/*.unsorted \
          "$work/badpaths" "$work/refusal.log"
    rmdir "$work"
}
trap cleanup EXIT
out="$work/plain.md"
red="$work/redacted.md"

swift "$spike" --home "$home" > "$out"
swift "$spike" --home "$home" --redact > "$red"

failures=0
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
same() { # name expected-file actual-file
    if cmp -s "$2" "$3"; then
        echo "ok: $1"
    else
        fail "$1 (diff expected actual follows)"
        diff "$2" "$3" || true
    fi
}

# The compressed man page copied into Box-Box/Contracts/terms.1, if one was found.
terms="$home/Library/CloudStorage/Box-Box/Contracts/terms.1"
box_files=2 box_logical=2540960 box_alloc=40960 box_ph=1 box_comp=0
if [ -f "$terms" ]; then
    compressed_size="$(stat -f %z "$terms")"
    compressed_alloc="$(( $(stat -f %b "$terms") * 512 ))"
    box_files=3
    box_logical=$((box_logical + compressed_size))
    box_alloc=$((box_alloc + compressed_alloc))
    box_comp=1
    [ "$compressed_alloc" -eq 0 ] && box_ph=2
else
    echo "note: no small compressed man page found; compressed-file checks skipped"
fi
gd="GoogleDrive-test.user@example.com"

# Totals. Columns: root, files, packages, dirs, logical, allocated, placeholders loose,
# placeholders strict, dataless, compressed, zero-byte, hard links, symlinks, other types,
# errors. DeepPaths is left out: where its walk stops depends on the base path length.
cat > "$work/totals.expected" <<EOF
com~apple~CloudDocs|3|1|1|2001000|4096|1|1|0|0|0|0|0|0|0
Dropbox|4|1|2|3008192|8192|1|1|0|0|1|1|2|1|0
$gd|7|0|5|11528672|28672|2|2|0|0|0|0|0|0|0
OneDrive-Contoso|2|0|2|5000300|4096|1|1|0|0|0|0|0|0|1
OneDrive-Personal|4|0|2|771010|24576|2|2|0|0|0|0|0|0|0
Box-Box|$box_files|0|1|$box_logical|$box_alloc|$box_ph|$box_ph|0|$box_comp|0|0|0|0|0
Family Files|1|0|0|4096|4096|0|0|0|0|0|0|0|0|0
ProtonDrive-test.user@example.com|1|0|0|4096|4096|0|0|0|0|0|0|0|0|0
EOF
awk -F' *[|] *' '
    /^## Totals/ { inside = 1; next }
    /^## / { inside = 0 }
    inside && /^[|] / && $2 != "Provider" && $2 != "---" && $3 != "DeepPaths" {
        print $3 "|" $4 "|" $5 "|" $6 "|" $7 "|" $9 "|" $11 "|" $12 "|" $13 "|" $14 "|" \
              $15 "|" $16 "|" $17 "|" $18 "|" $19
    }' "$out" > "$work/totals.actual"
same "totals for 8 roots" "$work/totals.expected" "$work/totals.actual"

# Placeholder samples: path, logical, allocated, status, loose, strict, dataless,
# compressed. Escaped pipes in names are swapped for <PIPE> before splitting.
samples() { # file
    sed 's/\\|/<PIPE>/g' "$1" | awk -F' *[|] *' '
        /^## Placeholder samples/ { inside = 1; next }
        /^## / { inside = 0 }
        inside && /^[|] / && $2 != "Path" && $2 != "---" {
            print $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7 "|" $8 "|" $9
        }' | LC_ALL=C sort
}
{
    echo "com~apple~CloudDocs/Documents/report.pdf|2000000|0|none|yes|yes|no|no"
    echo "Dropbox/Photos/trip/day1.jpg|3000000|0|none|yes|yes|no|no"
    echo "$gd/My Drive/Projects/plan.docx|1500000|0|none|yes|yes|no|no"
    echo "$gd/My Drive/Projects/old/archive.zip|10000000|0|none|yes|yes|no|no"
    echo "OneDrive-Contoso/Shared/q3.pptx|5000000|0|none|yes|yes|no|no"
    echo "OneDrive-Personal/Pictures/pic.png|750000|0|none|yes|yes|no|no"
    echo "OneDrive-Personal/Pictures/a<PIPE>b.png|1000|0|none|yes|yes|no|no"
    echo "Box-Box/Contracts/msa.pdf|2500000|0|none|yes|yes|no|no"
    if [ "$box_ph" -eq 2 ]; then
        echo "Box-Box/Contracts/terms.1|$compressed_size|0|none|yes|yes|no|yes"
    fi
} | LC_ALL=C sort > "$work/samples.expected"
samples "$out" > "$work/samples.actual"
same "placeholder samples" "$work/samples.expected" "$work/samples.actual"

# Redacted samples: same values, every path a <file-NNNN> token with at most a short
# alphanumeric extension.
cut -d'|' -f2- "$work/samples.expected" | LC_ALL=C sort > "$work/rsamples.expected"
samples "$red" > "$work/rsamples.raw"
cut -d'|' -f2- "$work/rsamples.raw" | LC_ALL=C sort > "$work/rsamples.actual"
same "redacted placeholder sample values" "$work/rsamples.expected" "$work/rsamples.actual"
if cut -d'|' -f1 "$work/rsamples.raw" \
    | grep -Ev '^[^/]+/<file-[0-9]{4}>(\.[A-Za-z0-9]+)?$' > "$work/badpaths"; then
    fail "redacted sample paths not tokenized: $(cat "$work/badpaths")"
fi

# Extended attributes other than com.apple.provenance, which macOS adds on its own.
xattrs() { # file
    awk '
        /^## Extended attributes/ { inside = 1; next }
        /^## / { inside = 0 }
        inside && /^### / { root = substr($0, 5); next }
        inside && /^  - / && !/com[.]apple[.]provenance/ { print root "|" $0 }' "$1" \
        | sed 's/<xattr-[0-9]*>/<xattr>/g' | LC_ALL=C sort
}
cat > "$work/xattrs.unsorted" <<EOF
com~apple~CloudDocs|  - com.example.state (7 bytes): UTF-8 text: "evicted"
Dropbox|  - com.example.provider.item-id (9 bytes): UTF-8 text: "item-0042"
Dropbox|  - com.dropbox.attrs (1 bytes): UTF-8 text: "x"
Dropbox|  - com.dropbox.ignored (1 bytes): hex text, 1 chars: "1"
$gd|  - com.google.drivefs.owner.test.user.example.com (1 bytes): hex text, 1 chars: "1"
$gd|  - com.example.content-sha256 (64 bytes): hex text, 64 chars: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822c..."
$gd|  - com.example.owner.someone@example.org (3 bytes): UTF-8 text: "yes"
OneDrive-Personal|  - com.example.blob (200 bytes): (value not read)
EOF
LC_ALL=C sort "$work/xattrs.unsorted" > "$work/xattrs.expected"
xattrs "$out" > "$work/xattrs.actual"
same "extended attributes" "$work/xattrs.expected" "$work/xattrs.actual"

cat > "$work/rxattrs.unsorted" <<EOF
com~apple~CloudDocs|  - <xattr> (7 bytes): UTF-8 text
Dropbox|  - <xattr> (9 bytes): UTF-8 text
Dropbox|  - com.dropbox.<xattr> (1 bytes): UTF-8 text
Dropbox|  - com.dropbox.ignored (1 bytes): hex text, 1 chars
GoogleDrive-<account-1>|  - com.google.<xattr> (1 bytes): hex text, 1 chars
GoogleDrive-<account-1>|  - <xattr> (64 bytes): hex text, 64 chars
GoogleDrive-<account-1>|  - <xattr> (3 bytes): UTF-8 text
OneDrive-<account-3>|  - <xattr> (200 bytes): (value not read)
EOF
LC_ALL=C sort "$work/rxattrs.unsorted" > "$work/rxattrs.expected"
xattrs "$red" > "$work/rxattrs.actual"
same "redacted extended attributes" "$work/rxattrs.expected" "$work/rxattrs.actual"

# Roots: one status per provider, unrecognized entries listed, nothing "not installed".
grep -q '^| Unrecognized | stray-file.txt | not a directory |$' "$out" \
    || fail "stray file under CloudStorage not listed as not a directory"
for name in "ProtonDrive-test.user@example.com" "Family Files" "DeepPaths"; do
    grep -q "^| Unrecognized | $name | unrecognized, walked |$" "$out" \
        || fail "unrecognized root $name not listed"
done
grep -q 'not installed' "$out" && fail "a provider in the fake tree is reported not installed"
grep -q 'iCloud~com~example~notes' "$out" && fail "non-CloudDocs iCloud container was listed"
grep -q 'DS_Store' "$out" && fail "hidden CloudStorage entry was listed"

# Errors carry the POSIX errno; the long path is explained.
grep -q 'locked: NSCocoaErrorDomain 257, errno 13 Permission denied$' "$out" \
    || fail "unreadable folder error missing or without errno"
grep -q 'NSCocoaErrorDomain 258, errno 63 .*PATH_MAX' "$out" \
    || fail "long-path error missing errno or PATH_MAX hint"
grep -q '^- Dataless materialization: off for this process' "$out" \
    || fail "materialization was not disabled"

# Packages report no fileSize: one per package root.
nofs="$(awk -F' *[|] *' '/^## Ubiquity/ { inside = 1; next } /^## / { inside = 0 }
    inside && ($2 == "com~apple~CloudDocs" || $2 == "Dropbox") { print $2 "=" $8 }' "$out" \
    | tr '\n' ' ')"
[ "$nofs" = "com~apple~CloudDocs=1 Dropbox=1 " ] \
    || fail "expected one package without fileSize in iCloud Drive and Dropbox, got: $nofs"

# Names with a newline or pipe never break a line or a table row.
grep -qF 'OneDrive-Personal/Documents/line\nbreak.txt' "$out" \
    || fail "newline in a file name was not escaped"
for f in "$out" "$red"; do
    bad="$(awk '
        /^[|] / {
            line = $0; gsub(/\\[|]/, "", line); n = gsub(/[|]/, "|", line)
            if (!intable) { cols = n; intable = 1 } else if (n != cols) { print NR ": " $0 }
            next
        }
        { intable = 0 }' "$f")"
    [ -z "$bad" ] || fail "table row with wrong column count in $(basename "$f"): $bad"
done

# Redacted output must not leak account suffixes, root names, file names, attribute names
# or values, or the home path.
for leak in "test.user@example.com" "example.org" "someone" "Contoso" "OneDrive-Personal" \
            "Family Files" "DeepPaths" "ProtonDrive" "Hale" "Budget" "report.pdf" \
            "item-0042" "evicted" "level_1" "line\\nbreak" "Smith" "drivefs" "owner" \
            "$home"; do
    grep -qF -- "$leak" "$red" && fail "redacted output contains \"$leak\""
done
grep -Eq '<file-[0-9]{4}>\.com' "$red" && fail "redacted output kept .com on an email-like name"
grep -q '^| Unrecognized | <unrecognized-[0-9]*> |' "$red" \
    || fail "redacted output has no unrecognized placeholder"
rows="$(awk '/^## Totals/ { inside = 1; next } /^## / { inside = 0 }
    inside && /^[|] / && !/^[|] (Provider|---) / { n++ } END { print n + 0 }' "$red")"
[ "$rows" -eq 9 ] || fail "redacted Totals table has $rows rows, expected 9"

# make-fake-tree.sh must refuse every target that is not absent or a listable empty
# directory, and must leave the refused target untouched.
mkdir -p "$cases/full" "$cases/unlistable"
echo keep > "$cases/full/keep.txt"
echo keep > "$cases/unlistable/keep.txt"
chmod 300 "$cases/unlistable"
echo keep > "$cases/a-file"
mkdir "$cases/empty-target"
ln -s empty-target "$cases/link"
ln -s full "$cases/link-full"
for target in "$cases/full" "$cases/full/" "$cases/full//" "$cases/unlistable" \
              "$cases/a-file" "$cases/link" "$cases/link/" "$cases/link-full/" "/" ""; do
    if bash "$here/make-fake-tree.sh" "$target" > "$work/refusal.log" 2>&1; then
        fail "make-fake-tree.sh accepted \"$target\""
    elif ! grep -q '^refusing' "$work/refusal.log"; then
        fail "make-fake-tree.sh failed on \"$target\" without refusing: $(cat "$work/refusal.log")"
    fi
done
chmod u+rwx "$cases/unlistable"
[ "$(cat "$cases/full/keep.txt")" = keep ] || fail "refused non-empty target was modified"
[ "$(cat "$cases/unlistable/keep.txt")" = keep ] || fail "refused unlistable target was modified"
[ "$(cat "$cases/a-file")" = keep ] || fail "refused file target was modified"
[ -z "$(ls -A "$cases/empty-target")" ] || fail "symlink target was written through"
echo "ok: make-fake-tree.sh refusal cases"

if [ "$failures" -eq 0 ]; then
    echo "PASS"
else
    echo "$failures check(s) failed"
    exit 1
fi
