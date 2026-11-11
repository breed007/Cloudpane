# 404tools.app: Cloudpane page copy

Drop-in copy for the product page at https://404tools.app/cloudpane. Cloudpane is released
on GitHub as a signed and notarized download, so the page's download button goes to
https://github.com/breed007/Cloudpane/releases/latest. This file is the content, not the
template, so it can be pasted into whatever the page structure is without guessing at the
markup.

Screenshots to use: the set described in `docs/screenshots.md`, taken from the demo data, so
no real account, file name or path appears on the page.

The page names the five providers as compatibility, which the app's name, icon and subtitle
never do.

---

## Hero

**Cloudpane**
### Where does your cloud storage actually go?

You pay for two or three cloud services, and none of them will tell you how they overlap.
Cloudpane reads the cloud folders already on your Mac and answers in one scan: what each
service holds, where a file lives, what you store twice, whether any of it is really backed
up, and what it all costs per terabyte.

*Free and open source, with no account and no network connections.*

[Download for Mac](https://github.com/breed007/Cloudpane/releases/latest)

Signed and notarized by 404 Cybersecurity LLC. With Homebrew:
`brew install --cask breed007/tap/cloudpane`

---

## One scan, five answers

### Overview
How much is in each service and each account, and how much of it is only in the cloud. When
a service has not finished listing its folder on this Mac, Cloudpane says the scan may be
missing files.

### File search
Search every service at once by file name and see where each match lives. Reveal in Finder
and Copy path are the only things it will do with a file.

### Duplicates
Groups ranked by how much space the extra copies take, matched by name, size and date. Turn
on hashing for a folder to match by content. It never deletes anything; every group is yours
to review.

### 3-2-1 backup grade
A letter for every top-level folder, with the reason in plain words. Sync is not backup, so
a second cloud never raises the grade. Add a Time Machine backup, an external drive or a
NAS share, read-only, and Cloudpane checks which of your files it really holds. Files that
exist in exactly one place get their own list.

### Providers
Every account on your Mac with its status and the space it uses, and one plan per service,
entered once. Cloudpane works out the monthly cost, the cost per terabyte, the room
left, and how many months until you run out, from your own scan history. Bundles like Apple
One or Microsoft 365 are shown but kept out of the total. When one plan has room for another,
Cloudpane shows that option beside the backup grade, because canceling a service removes a
copy of your files.

---

## No logins, by design

All five services Cloudpane works with now sync through the
same part of macOS, and a file kept only in the cloud still leaves a placeholder on your Mac
with its real name, size and dates. Cloudpane reads those. It never asks for a password,
never connects to a service, and never reads or downloads a file's contents on its own.
Reading a folder may make the service's app fetch that folder's list, and the service may
then download items it keeps on your Mac by its own settings, just as after you open the
folder in Finder. The one exception is opt-in: hashing a cloud-only file to find
exact duplicates needs its contents, so Cloudpane shows how much would download and waits
for you to confirm.

For iCloud, it measures iCloud Drive exactly, can estimate Photos from the size of your
Photos library without opening a single photo, and lets you type in your total from System
Settings. Device backups, Mail and Messages are out of reach without your Apple Account or
Full Disk Access, and Cloudpane asks for neither.

---

## Reports you can share

Export a PDF with the overview, plans, backup grade, single points of failure, duplicate
totals and history. File paths, file and folder names, account names and backup labels are
left out unless you choose to include them. Plan names you typed stay in. CSV and JSON
exports of a full scan are there too.

---

## Privacy

- No analytics, crash reporting, accounts, ads or third-party code.
- The app has no permission to make a network connection, so it never goes online.
- It reads only the folders you grant, read-only, and never moves, copies, renames, uploads
  or deletes a file.
- Everything it records stays on your Mac. A report leaves only when you share it.

[Privacy Policy] · [Source code on GitHub](https://github.com/breed007/Cloudpane)

---

## Works with

iCloud Drive, Dropbox, Google Drive, OneDrive and Box, through their current Mac apps. Each
service has to be installed and signed in on the Mac you scan; Cloudpane cannot see a
service you only use in a browser.

---

## Requirements

macOS 14 Sonoma or later · Apple silicon or Intel · Free, MIT License

---

Notes:

- "[Privacy Policy]" links to the site's privacy page. Cloudpane's own policy text is
  `docs/privacy-policy.md`.
- "All five services … sync through the same part of macOS" refers to File Provider. The
  real-provider spike confirmed the placeholder claim for four of them on October 25, 2026
  and for iCloud Drive on November 1 (Spike/RESULTS.md). If a provider ever fails it, rewrite the paragraph.
