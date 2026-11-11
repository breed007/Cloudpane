#!/bin/bash
# Builds a fake home directory that mimics the File Provider layout Cloudpane scans.
#
# Usage: bash Spike/make-fake-tree.sh <dir>
#
# <dir> must not exist (it is created) or must be an empty directory that can be read and
# listed. Symbolic links and anything else are refused. The script never deletes anything; to
# rebuild, remove the folder yourself first. The tree holds one deliberately unreadable folder,
# so run chmod u+rwx on <dir>/Library/CloudStorage/OneDrive-Contoso/Shared/locked before
# removing it.
#
# Run the spike against it with
#   swift Spike/footprint-spike.swift --home <dir>
# and check the output with Spike/check-fake-tree.sh <dir>.
#
# Placeholders are simulated with sparse files (logical size > 0, allocated size 0). Sparse
# files are not ubiquitous items and never carry SF_DATALESS, so isUbiquitousItem is false,
# the download status is nil, and the dataless count is 0 for every file in this tree. The
# expected numbers live in check-fake-tree.sh and assume APFS with 4096-byte allocation blocks.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <dir>" >&2
    exit 2
fi

home="$1"
# Strip trailing slashes first, so "link/" is tested as the link itself.
while [[ "$home" == */ && "$home" != "/" ]]; do home="${home%/}"; done

if [[ -z "$home" || "$home" == "/" ]]; then
    echo "refusing: \"$1\" is not a usable target" >&2
    exit 1
elif [[ -L "$home" ]]; then
    echo "refusing: $home is a symbolic link" >&2
    exit 1
elif [[ -e "$home" ]]; then
    if [[ ! -d "$home" ]]; then
        echo "refusing: $home exists and is not a directory" >&2
        exit 1
    elif [[ ! -r "$home" || ! -x "$home" ]]; then
        echo "refusing: $home exists but cannot be read and listed" >&2
        exit 1
    fi
    # The listing itself must succeed; an unlistable directory is not "empty".
    if ! listing="$(ls -A "$home")"; then
        echo "refusing: could not list $home" >&2
        exit 1
    elif [[ -n "$listing" ]]; then
        echo "refusing: $home is not empty. Remove it yourself to rebuild." >&2
        exit 1
    fi
fi
mkdir -p "$home"

docs="$home/Library/Mobile Documents"
icloud="$docs/com~apple~CloudDocs"
cs="$home/Library/CloudStorage"

# Real bytes from /dev/urandom so APFS allocates every block and nothing compresses.
real() { mkdir -p "$(dirname "$2")"; head -c "$1" /dev/urandom > "$2"; }
# Sparse file: logical size set, no blocks allocated. (mkfile -n allocates on APFS.)
sparse() { mkdir -p "$(dirname "$2")"; truncate -s "$1" "$2"; }

# iCloud Drive
real 1000 "$icloud/Documents/notes.txt"
sparse 2000000 "$icloud/Documents/report.pdf"
real 500 "$icloud/.hidden-config"                                    # hidden: skipped
real 8192 "$icloud/Archive.photoslibrary/database/Photos.sqlite"     # inside package: skipped
real 4096 "$icloud/Archive.photoslibrary/originals/IMG_0001.heic"    # inside package: skipped
# Another app's iCloud container: not CloudDocs, never walked or listed
real 4096 "$docs/iCloud~com~example~notes/Documents/a.txt"

# Dropbox
db="$cs/Dropbox"
real 8192 "$db/Photos/beach.jpg"
ln "$db/Photos/beach.jpg" "$db/Photos/beach-hardlink.jpg"            # hard link: counted once
sparse 3000000 "$db/Photos/trip/day1.jpg"
mkdir -p "$db" && : > "$db/empty.txt"                                # zero-byte file
mkfifo "$db/pipe.fifo"                                               # FIFO: skipped
real 4096 "$db/Tool.app/Contents/MacOS/tool"                         # inside package: skipped
real 200 "$db/Tool.app/Contents/Info.plist"                          # inside package: skipped
real 4096 "$db/.dropbox.cache/cached.bin"                            # hidden dir: skipped
real 4096 "$home/outside/big.bin"                                    # only reachable by symlink
ln -s ../../../outside "$db/link-to-outside"                         # symlink to dir: skipped
ln -s Photos/beach.jpg "$db/link-to-file"                            # symlink to file: skipped

# Google Drive, one account with My Drive and Shared drives
gd="$cs/GoogleDrive-test.user@example.com"
real 12288 "$gd/My Drive/Budget.xlsx"
real 4096 "$gd/My Drive/tax.Hale-Family"                             # long extension: dropped
real 4096 "$gd/My Drive/someone@example.com"                         # email name: no extension
real 4096 "$gd/My Drive/Letter.Smith"                                # not a known type: dropped
sparse 1500000 "$gd/My Drive/Projects/plan.docx"
sparse 10000000 "$gd/My Drive/Projects/old/archive.zip"
real 4096 "$gd/Shared drives/Team/spec.pdf"
real 100 "$gd/Shared drives/Team/flagged.txt"
chflags hidden "$gd/Shared drives/Team/flagged.txt"                  # UF_HIDDEN: skipped

# OneDrive, two accounts
odp="$cs/OneDrive-Personal"
real 20000 "$odp/Documents/cv.docx"
real 10 "$odp/Documents/line"$'\n'"break.txt"                        # newline in a name
sparse 750000 "$odp/Pictures/pic.png"
sparse 1000 "$odp/Pictures/a|b.png"                                  # pipe in a name

odc="$cs/OneDrive-Contoso"
sparse 5000000 "$odc/Shared/q3.pptx"
real 300 "$odc/Shared/readme.md"
real 4096 "$odc/Shared/locked/secret.txt"
chmod 000 "$odc/Shared/locked"                                       # unreadable: one error

# Box
bx="$cs/Box-Box"
real 40960 "$bx/Contracts/nda.pdf"
sparse 2500000 "$bx/Contracts/msa.pdf"
# A small HFS-compressed file. Data this small lives inline in the decmpfs attribute, so it
# reports allocated 0 while being fully local. (A 905-byte page measured 4096 allocated.) ditto --hfsCompression does not compress on this
# setup, so copy a small compressed man page; ditto keeps the compression.
# awk exits early, so ls may die of SIGPIPE; "|| true" keeps pipefail from aborting.
source_page="$({ ls -lO /usr/share/man/man1 2>/dev/null || true; } \
    | awk '$5 == "compressed" && $6 >= 20 && $6 <= 300 { print $NF; exit }')"
if [[ -n "$source_page" ]]; then
    ditto "/usr/share/man/man1/$source_page" "$bx/Contracts/terms.1"
fi

# Unrecognized CloudStorage entries
real 4096 "$cs/ProtonDrive-test.user@example.com/file.bin"
real 4096 "$cs/Family Files/file.bin"                                # no hyphen: fully redacted
real 10 "$cs/stray-file.txt"
real 10 "$cs/.DS_Store"                                              # hidden: not listed

# A path longer than PATH_MAX (1024 bytes). The enumerator stops below the limit and logs
# NSCocoaErrorDomain 258. Built with relative mkdir steps because the full path is too long
# for mkdir -p. Its own root, because where the walk stops depends on the base path length.
deep="$cs/DeepPaths"
mkdir -p "$deep"
(
    cd "$deep"
    for i in $(seq 1 14); do
        d="level_${i}_abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmn"
        mkdir "$d"
        cd "$d"
    done
    head -c 10 /dev/urandom > deep.bin
)

# Extended attributes (small values are previewed, the 200-byte one is not read)
xattr -w com.example.provider.item-id "item-0042" "$db/Photos/beach.jpg"
xattr -w com.dropbox.attrs "x" "$db/Photos/beach.jpg"                # vendor prefix only
xattr -w com.dropbox.ignored "1" "$db/Photos/beach.jpg"              # allowlisted: kept
xattr -w com.example.content-sha256 \
    "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08" "$gd/My Drive/Budget.xlsx"
xattr -w "com.example.owner.someone@example.org" "yes" "$gd/My Drive/Budget.xlsx"
xattr -w com.google.drivefs.owner.test.user.example.com "1" "$gd/My Drive/Budget.xlsx"
xattr -w com.example.state "evicted" "$icloud/Documents/report.pdf"
xattr -w com.example.blob "$(printf 'x%.0s' {1..200})" "$odp/Documents/cv.docx"

echo "Fake home built at $home"
