# M0 spike results

Status: **go.** Real runs on October 25, 2026, with Dropbox, Google Drive, OneDrive and Box
signed in and iCloud Drive turned on. Cloud-only files report their true size. Folders a
provider has not listed yet need folder listing allowed during the walk; with the
`--allow-folder-listing` walk, every folder listed and the spike read no file's contents.
OneDrive downloaded one small file on its own afterward (see "Correction"). iCloud Drive was
empty on that Mac, so it was checked separately on November 1 with a test file (see "iCloud
Drive check"). See "First real run", "Folder-listing run" and the go/no-go at the end.

## Real data

Run the spike twice on a Mac with the providers installed and signed in (see the README
requirements):

1. `swift Spike/footprint-spike.swift > Spike/RESULTS-local.md` keeps real names and is ignored
   by git. Use it for the by-eye checks below, which need real file names.
2. `swift Spike/footprint-spike.swift --redact` is the version to paste here. It replaces
   account suffixes, unrecognized root names, file paths and attribute names that are not on
   an allowlist with placeholders, and prints attribute values only as a kind and a length.

Web numbers come from each provider's own usage page. One row per account root. The web file
count is optional; most usage pages do not show one.

Scan date: 2026-10-25T22:07:44Z
macOS version: 27.0.1 (26A434)

| Provider | Account root | Files | Logical (scan) | Allocated (scan) | Placeholders (loose) | Placeholders (strict) | Dataless (st_flags) | Walk time | Web UI used | Web UI file count (optional) | Difference | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| iCloud Drive | com~apple~CloudDocs | 0 | 0 | 0 | 0 | 0 | 0 | 46 ms | | | | Empty root, no errors |
| Dropbox | Dropbox | 147 | 955,661,056 | 0 | 147 | 147 | 147 | 3,462 ms | | | | Every file cloud-only, every folder listed, no errors |
| Google Drive | GoogleDrive-&lt;account-1&gt; | 0 | 0 | 0 | 0 | 0 | 0 | 1,960 ms | | | | 1 dataless folder not walked (errno 11); nothing else seen |
| OneDrive | OneDrive-&lt;account-2&gt; | 4 | 532,221 | 0 | 4 | 4 | 4 | 1,251 ms | | | | 18 dataless folders not walked (errno 11) |
| Box | Box-Box | 3 | 3,284,367 | 0 | 3 | 3 | 3 | 1,455 ms | | | | 16 dataless folders not walked (errno 11) |

### First real run, October 25, 2026

1. **Sizes hold.** Every cloud-only file seen reports its real logical size through
   `fileSizeKey` and an allocated size of 0. Examples: Dropbox photos of 6.7 to 7.2 MB, a
   OneDrive PDF of 493 KB, Box photos of 1.3 and 1.9 MB. The web UI comparison is still to
   do.
2. **The dataless flag is reliable, and both placeholder definitions agree with it.** Loose,
   strict and SF_DATALESS give the same count on every root. File Provider roots report the
   items as ubiquitous with status `notDownloaded`, never nil.
3. **Cloud-only files also carry UF_COMPRESSED.** All 154 have the compressed flag set
   alongside SF_DATALESS. So the compressed flag cannot be read as "the data is on this
   Mac". Core's rule checks the dataless flag first, so it already handles this, but the
   strict rule's compressed exclusion would be wrong without that order.
4. **Folders the provider has not listed yet cannot be walked with materialization off.**
   Listing them fails with errno 11 (EDEADLK), the blocked-materialization error. Google
   Drive showed nothing at all: its one top-level folder was dataless. OneDrive lost 18
   folders and Box lost 16. Dropbox had listed everything already, so it walked fully. This
   is the risk the spike was built to catch, and Cloudpane's scanner (same policy) has the
   same gap.
5. **No local content hash.** Dropbox puts two `com.dropbox.*` attributes on every file, one
   25 or 26 bytes of binary, too short for SHA-1 or SHA-256 and most likely an item
   identifier. OneDrive and Box add only `com.apple.FinderInfo`. Exact duplicates still need
   opt-in hashing.
6. **Walks are slow per file.** 147 Dropbox files took 3.5 s, which is the provider's
   metadata latency, not disk. A large library will need the progress UI and incremental
   updates that M4 built.

### Folder-listing run, October 25, 2026

`swift Spike/footprint-spike.swift --redact --allow-folder-listing`, run at
2026-10-25T22:25:08Z, about 18 minutes after the first run.

| Provider | Account root | Files | Logical (scan) | Allocated (scan) | Dataless (st_flags) | Cloud-only folders listed | Folders still cloud-only | Now local | Errors | Walk time |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| iCloud Drive | com~apple~CloudDocs | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 25 ms |
| Dropbox | Dropbox | 147 | 955,661,056 | 0 | 147 | 0 | 0 | 0 | 0 | 282 ms |
| Google Drive | GoogleDrive-&lt;account-1&gt; | 236 | 319,892,295 | 0 | 236 | 34 | 0 | 0 | 0 | 10,346 ms |
| OneDrive | OneDrive-&lt;account-2&gt; | 1,486 | 5,025,866,783 | 0 | 1,486 | 195 | 0 | 0 | 0 | 39,917 ms |
| Box | Box-Box | 284 | 30,953,160,551 | 0 | 284 | 41 | 0 | 0 | 0 | 13,462 ms |

1. **Every folder listed, and the walk read no file contents.** The walk listed 270 folders
   the providers had not listed on this Mac before, and none stayed cloud-only. After each
   root, all 2,153 files that were cloud-only when visited were read again: none had gained
   local data at that point and none had disappeared. Allocated size stayed 0 everywhere.
   See the correction below: one file gained data later in the run, downloaded by OneDrive
   itself.

   **Correction, found in testing.** A 168-byte OneNote notebook shortcut (`.url`) in OneDrive
   gained local data at 22:26:25Z, after its root's re-check and while the spike was still
   sampling attributes. The unified log shows fileproviderd running
   `fetch-content why:materialization|itemChangedRemotely|backgroundWork sched:background`
   for the OneDrive domain from its own background-download scheduler, which fires about
   once a minute. The spike's listings appear only as `populate-directory … sched:default`
   jobs, and that fetch was the only content fetch in the run's window. So the spike did not
   read the file: listing the folder made OneDrive aware of the item, and OneDrive's own
   policy downloaded it, as it would after the folder is opened in Finder. That file is the
   one-file difference between the spike's 2,153 cloud-only files and Core's later 2,152.
2. **The errno 11 errors are gone.** All 35 from the first run were folder listings, and
   allowing the listing removed every one.
3. **Sizes still hold.** The newly seen files report real sizes: a 51 MB Google Drive video,
   OneDrive documents from 9 KB to 576 KB, and 30.95 GB across Box. Loose, strict and
   SF_DATALESS still agree, except one zero-byte OneDrive file, which is dataless with
   logical size 0 and so correctly counts as no placeholder.
4. **First listing is the slow part.** OneDrive took 40 s for 195 folders and 1,486 files,
   Google Drive 10 s, and Box 13 s. Dropbox, already listed, dropped from 3.5 s to 0.3 s on a
   warm run. The scanner's progress UI has to cover a first scan of this length.
5. **Google Drive adds one `com.google.*` attribute**, 33 to 49 bytes of UTF-8 text, the
   size of a Drive item ID. Like Dropbox's, it is not a content hash.
6. **Cross-provider duplicates show up already.** The same two photos appear in Dropbox and
   Box at identical sizes (2,532,718 and 2,710,678 bytes), a useful real case for M4's
   duplicate tiers.

Things to check, using `Spike/RESULTS-local.md`:

- Placeholder samples: open each sampled file's page in the provider's web UI and compare its
  size with the "Logical bytes" column. Logical size must match the real file size, not 0 and
  not the allocated size.
- The three placeholder columns. "Dataless (st_flags)" is the kernel's own SF_DATALESS flag and
  is the ground truth; the two definitions are only as good as their agreement with it. Where
  they differ, the "Ubiquity and download status" table and the Compressed column show why.
  The result settles which definition M1 uses.
- Compressed files. A small file that macOS stores compressed (UF_COMPRESSED) keeps its data in
  a file attribute and reports allocated size 0 while being fully on the Mac. Both
  allocated-based definitions count it as a placeholder. Any row where Compressed is non-zero
  and the placeholder counts exceed the dataless count is this effect, not a provider quirk.
- Errors, especially `errno 11 Resource deadlock avoided` (EDEADLK). The spike disables
  dataless-file materialization for its own process so that nothing can trigger a download.
  The getiopolicy_np(3) man page does not say which errno a blocked operation returns, and it
  is untested whether listing a dataless folder on a real provider is blocked. If it is, the
  walk loses everything below that folder. Look for errno 11 lines, and for a non-zero
  "Dataless dirs" count next to a file total lower than the web number.
- `NSCocoaErrorDomain 258, errno 63` means a path is longer than PATH_MAX (1024 bytes) and
  nothing below it was walked. The error line names the deepest folder reached.
- Download status for File Provider roots. If Dropbox, Google Drive, OneDrive and Box report
  a nil status for every file, the allocated-based tests rest on allocated size alone and the
  dataless flag matters more.
- Extended attributes: any attribute that looks like a content hash (a 40- or 64-character hex
  string) or a stable item identifier. A local hash would make exact duplicate matching
  possible without hashing anything.
- Web totals that include trash, version history or files shared with you count bytes the scan
  cannot see. Note it in the notes column rather than treating it as a mismatch.
- iCloud Drive: the web total may include app folders such as Pages or Numbers, which live in
  other containers under `~/Library/Mobile Documents` and are outside the CloudDocs root the
  spike walks (to verify).

## Fake-tree verification

Run on 2026-10-24, macOS 27.0.1, Swift 6.4, APFS with 4096-byte allocation blocks.

```sh
bash Spike/make-fake-tree.sh <scratch>/fake-home
sh Spike/check-fake-tree.sh <scratch>/fake-home
```

`make-fake-tree.sh` only builds into a path that does not exist or an empty directory it can
read and list. It never deletes; to rebuild, run `chmod u+rwx` on the tree's
`Library/CloudStorage/OneDrive-Contoso/Shared/locked` folder, remove the tree yourself, and
run it again.

Result: **pass**, under both `sh` and `bash`. The checker compares the totals, every
placeholder sample row, every extended attribute line other than `com.apple.provenance`, and
the redacted versions of the samples and attributes. It also checks that every table row has
the right number of columns and that the redacted run leaks no account suffix, root name, file
name, attribute name or value, or home path. Finally, it runs `make-fake-tree.sh` against
targets it must refuse (a non-empty directory with and without trailing slashes, a directory
with mode 300 that cannot be listed, a file, symbolic links with and without a trailing slash,
`/` and an empty string) and confirms each was refused and left untouched. Five deliberately
broken copies of the spike each made it fail: sample columns swapped, attribute values dropped,
every extension kept in redacted paths, extensions kept without the type check, and
vendor-prefixed attribute names printed verbatim.

| Account root | Files | Packages | Dirs | Logical bytes | Allocated bytes | Placeholders (both) | Dataless | Compressed | Zero-byte | Hard links skipped | Symlinks skipped | Other types skipped | Errors | Walk ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| com~apple~CloudDocs | 3 | 1 | 1 | 2001000 | 4096 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 6.9 |
| Dropbox | 4 | 1 | 2 | 3008192 | 8192 | 1 | 0 | 0 | 1 | 1 | 2 | 1 | 0 | 13.6 |
| GoogleDrive-\<account-1\> | 7 | 0 | 5 | 11528672 | 28672 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 3.5 |
| OneDrive-\<account-2\> | 2 | 0 | 2 | 5000300 | 4096 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1.6 |
| OneDrive-\<account-3\> | 4 | 0 | 2 | 771010 | 24576 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2.1 |
| Box-Box | 3 | 0 | 1 | 2541035 | 40960 | 2 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1.2 |
| \<unrecognized-2\> | 1 | 0 | 0 | 4096 | 4096 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.5 |
| \<unrecognized-3\> | 1 | 0 | 0 | 4096 | 4096 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.4 |

The long-path root (`<unrecognized-1>`) is checked for its error line rather than its counts,
because where its walk stops depends on the length of the base path. Box-Box includes a
75-byte compressed file copied from a system man page; the checker reads its size with
`stat`, so the Box numbers adapt if a different page is picked on another macOS version.
Walk times are from one run on a tree of a few dozen files and say nothing about real scale.

What the fake tree confirmed:

- Hidden items are skipped, both dot-names and files with the `UF_HIDDEN` flag.
- `.photoslibrary` and `.app` bundles are counted as one item each, and nothing inside them is
  counted.
- Only regular files and packages are counted. A second hard link to a counted file, symbolic
  links (including one that points outside the root) and a FIFO are skipped and counted in
  their own columns.
- An unreadable folder produces one logged error with its errno
  (`NSCocoaErrorDomain 257, errno 13 Permission denied`) and the walk continues.
- A path over 1024 bytes stops the walk below that point and logs
  `NSCocoaErrorDomain 258, errno 63 File name too long` with a note saying so. Walking past
  the limit would need a descriptor-based walker (openat), which is left for M1 if real data
  ever has such paths.
- Two OneDrive accounts produce two rows. Folders under `CloudStorage` that match no rule are
  walked and listed as unrecognized, and a stray file there is listed as "not a directory".
- Other iCloud containers under `Mobile Documents` are neither walked nor listed.
- File names containing a pipe or a newline are escaped and never break a table or a line.
- Redaction keeps an extension only when the system knows it as a declared type
  (`UTType(filenameExtension:)` is not dynamic), and never on a name that contains `@`, so
  `Letter.Smith`, `tax.Hale-Family` and `someone@example.com` lose their suffixes while `.pdf`
  and `.docx` stay. A surname that happens to be a registered extension would still show; that
  is the limit of this rule.
- Attribute names are printed verbatim in redacted output only if they are on an explicit
  allowlist: `com.apple.provenance`, `com.apple.quarantine`, `com.apple.FinderInfo`,
  `com.apple.ResourceFork`, `com.apple.lastuseddate#PS`, `com.apple.decmpfs`, Spotlight keys
  of the form `com.apple.metadata:kMDItem...`, and `com.dropbox.ignored`, which Dropbox
  documents for excluding a file from sync. Other names under a known vendor prefix keep only
  the prefix (`com.google.<xattr-3>`), so an identity embedded in a name such as
  `com.google.drivefs.owner.<email>` does not leak. Everything else becomes `<xattr-N>`, a
  per-run counter rather than a hash, so it cannot be reversed by guessing. Unredacted output
  shows full names.

Checked by hand against separate repro trees, not in the checker:

- Each provider gets exactly one status. A provider whose root is a file or a symbolic link
  shows that, not an extra "not installed" row.
- An unreadable `CloudStorage` shows every provider under it as "unknown (could not read
  Library/CloudStorage: ... errno 13 Permission denied)" instead of "not installed".
- A symbolic link at `Library/CloudStorage` is not followed. Providers under it show as
  "unknown (Library/CloudStorage is a symbolic link, not followed)". The real layout never
  uses a link there, and following one would take the walk outside the folders Cloudpane is
  meant to read.

Found while building it, and relevant to M1:

- A package directory reports no `fileSizeKey` and no `totalFileAllocatedSizeKey`. Counted as
  one leaf, a package contributes 0 bytes. M1 has to decide how to size packages (for example,
  summing their contents for the total while still showing the package as one item). The
  spike reports these under "No fileSize" and does not count them as zero-byte files or
  placeholders.
- Allocated size 0 is not proof of a placeholder. A compressed local file can report it too,
  which is why the spike reads SF_DATALESS from `lstat`.
- `mkfile -n` does not create a sparse file on this APFS volume; the result was fully
  allocated. `truncate -s` does, so the fake tree uses `truncate` throughout.
  `ditto --hfsCompression` did not compress a file here either, which is why the tree copies
  an already compressed system file.
- Every file the scripts created carries a `com.apple.provenance` attribute (11 bytes) that
  macOS adds on its own. Expect it on real data too; it is not provider metadata.
- Hard links are counted once per run, by device and inode. A hard link spanning two provider
  roots would be counted under whichever root is walked first.

What the fake tree cannot show:

- Ubiquity keys and the dataless flag. Sparse files are not ubiquitous items and never carry
  SF_DATALESS, so `isUbiquitousItemKey` is false, the download status is nil and the dataless
  count is 0 for every file. Both placeholder definitions reduce to "allocated size is 0" and
  always agree here. Only real data can show where they differ from each other and from the
  dataless flag.
- Real placeholder behavior: whether a dataless file reports its true logical size, 0, or its
  allocated size.
- Provider attributes, partial sync (selective sync, "Choose folders"), dataless folders, and
  how long a walk takes on a real account.
- Whether disabling dataless materialization for the process ever blocks a metadata read or a
  folder listing. On this tree no item was dataless.

## Go/no-go

The decision is open until the spike has run against at least one real account per provider.
The local-first premise holds if every provider's placeholders report their true logical size
through `fileSizeKey`, so the scan's logical total is close to the provider's web number once
trash and shared items are accounted for. The finding that would change the architecture is a
provider whose placeholders report a logical size of 0, or a logical size equal to the
allocated size (only the bytes stored on the Mac). If that happens, the size of cloud-only
files is not available locally for that provider. The only remaining source would be the
provider's API, which needs the network and an account login, and both are ruled out by the
project's rules. That provider would then have to be dropped or shown as a partial view, and
the decision is made again before M1 starts.

**Result, October 25, 2026: go on sizes, with one decision needed.** No provider reported a
size of 0 or an allocated-equals-logical placeholder, so the size premise holds for Dropbox,
OneDrive and Box, and nothing contradicts it for Google Drive. The new problem is
enumeration: with dataless materialization off for the whole walk, any folder the provider
has not yet listed on this Mac is invisible, and on a fresh Google Drive that is everything.
The likely fix is to allow materialization on the walk thread for folder listings only,
while the walker keeps never opening a file, so file contents still never download. Listing
a folder makes the provider fetch its directory listing, the same thing Finder does when you
open the folder. That is a change to the read-only rule's wording, so it needs approval
first, and a spike run with that setting must show the dataless file count unchanged before
Core adopts it.

Testing it was approved on October 25, 2026. The spike's `--allow-folder-listing` option
turns materialization on for the walk thread only around each folder listing call, with no
attributes prefetched, and back off before any file is examined. After each root it reads
every cloud-only file again and reports any that gained local data in a "Folder listing
check" section. On the fake tree both walks give identical totals.

**Result, folder-listing run, October 25, 2026: go.** "Now local" was 0 on every root, all
270 cloud-only folders listed, and the errno 11 errors disappeared. Core's scanner should
adopt the same rule: materialization on for the walk thread only around each folder listing
call, with nothing prefetched, and off for every file. The read-only rule then reads: Cloudpane
never reads or downloads a file's contents, except opt-in hashing. Listing a folder may make
the provider fetch that folder's list, and a provider may then download items it keeps local
by its own policy, as it would after the folder is opened in Finder. OneDrive did this for
one OneNote notebook shortcut.

### iCloud Drive check, November 1, 2026

iCloud Drive had no files on this Mac, so the claim was tested with one file, added
for the test. A 5,000,000-byte file of random data, so it could not compress, was written to the
root of iCloud Drive. It reported uploaded within seconds. `brctl evict` then removed the local
copy, as Remove Download in Finder does.

| Stage | Logical size | Allocated | Download status | SF_DATALESS |
| --- | --- | --- | --- | --- |
| After upload | 5,000,000 | 5,001,216 | current | no |
| After eviction | 5,000,000 | 0 | notDownloaded | yes (with UF_COMPRESSED, as on the other four) |

`swift Spike/footprint-spike.swift --redact` counted iCloud Drive as 1 file, 5,000,000 logical
bytes, 0 allocated, and 1 placeholder under the loose, strict and SF_DATALESS tests. The
`cloudpane-scan` CLI reported the same: 1 file, 5,000,000 bytes, 1 placeholder, 0 errors. The
file was then deleted, so it sits in iCloud's Recently Deleted for 30 days.

**Result: go on all five providers.** iCloud Drive placeholders report their true size like
Dropbox, Google Drive, OneDrive and Box. The `[VERIFY: real-provider spike]` markers in the
page copy are removed.
