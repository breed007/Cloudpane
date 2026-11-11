# Changelog

## 1.0, November 2026

First public release. Cloudpane reads the cloud folders already on your Mac and shows what
iCloud Drive, Dropbox, Google Drive, OneDrive and Box each hold, with no logins and no
network connections. It is read-only, sandboxed, signed with a Developer ID certificate and
notarized by Apple.

- Overview: totals per provider and account, split into what is on this Mac and what is only
  in the cloud, with a note when a provider has not finished listing a folder.
- File search: search every provider by file name. Reveal in Finder and Copy path are the
  only actions on a file.
- Duplicates: groups ranked by reclaimable space, matched by name, size and date, by size
  alone for large files, or by SHA-256 for folders with hashing turned on.
- Backup grade: a 3-2-1 letter per top-level folder and overall, with the reason for each.
  Another cloud copy never raises a grade; a backup location you add does.
- Providers: every account with its status and space used, and one plan per provider with
  its monthly cost, cost per terabyte, room left and months to full. Bundles are shown and
  kept out of the personal total. For iCloud, an optional Photos estimate and a total you
  can enter by hand.
- History: every scan is kept, and a file watcher records changes as they happen.
- Export: a scan as CSV or JSON, or a PDF report that leaves out file paths and names unless
  you include them.
- Help: the pages in `docs/help`, built into the app.
