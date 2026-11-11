---
title: Backup grade
order: 5
platforms: macOS, iOS
summary: How each folder is graded against the 3-2-1 rule, and how to raise the grade.
---
# Backup grade

The 3-2-1 rule asks for three copies of your files, on two kinds of storage, with one copy somewhere else. Cloudpane grades each top-level folder of each provider against it, and rolls the folders up into one letter. For Google Drive, a top-level folder is one inside My Drive or Shared drives.

## Sync is not backup

A cloud provider syncs: delete or damage a file, and the change reaches every synced copy. Another cloud copy never raises the grade. What raises it is a backup location: a Time Machine backup, a folder on an external drive, or a NAS share. Cloudpane reads it, read-only, and checks which of your cloud files it holds. You say whether each location is on-site or off-site.

A backup location whose disk is not connected is left out of the scan, so the grade sees no backup there until the disk is back and Cloudpane scans again.

<!-- macOS -->
Add backup locations in Settings. See [Settings](settings.md#backup-locations).
<!-- /macOS -->

A file counts as copied when a file there has the same name, the same size, and a modification date within 2 seconds. When both files are hashed, their hashes must agree too. A location counts as a copy of a folder when it holds at least 90% of it. When most files match by name and size but not by date, the folder's explanation says so, since the backup may have been made without keeping dates.

## The five checks

| Check | Passes when |
| --- | --- |
| Three copies | The folder is in three places: the provider's cloud, downloaded on this Mac, or a backup location. |
| Two kinds of storage | At least one copy is a backup, not a sync folder. |
| One copy off-site | A copy is off the Mac and outside the home. The provider's cloud is, so this passes for every synced folder. |
| Version history | The provider keeps earlier versions of files (see below). |
| More than one place | The folder is not only in the provider's cloud. |

## The letters

Cloudpane checks for F first, then works down from A:

- F: nothing in the folder is downloaded on this Mac or held by a backup.
- A: a backup holds it, and copies, kinds of storage, off-site and version history all pass.
- B: a backup holds it, and one of those four is missing.
- C: a backup holds it but more is missing, or no backup holds it and the provider keeps version history.
- D: no backup holds it, and the provider keeps no version history, or Cloudpane has not confirmed that it does.

The overall letter is the average of the folders' letters weighted by size, rounded down. Each folder's row explains its letter and its checks, and suggests a fix: keeping the folder downloaded, or adding a backup location. The fix is never another cloud.

## Version history by provider

| Provider | What Cloudpane uses |
| --- | --- |
| iCloud Drive | No version history. Deleted files can be recovered for 30 days, which is not a history of earlier versions. |
| Dropbox | Keeps old versions for 30 days on Basic, Plus and Family, 180 days on Professional and Essentials. |
| Google Drive | Keeps old versions for 30 days or until 100 newer versions exist. |
| OneDrive | Personal accounts keep the last 25 versions; work and school accounts follow the organization. |
| Box | The free plan keeps 1 version, which is no history; Personal Pro keeps 10. Counts as versioned only when a paid Box plan is entered in [Providers](providers.md). |
| Providers you add | Unknown, so never a pass. |

So without a backup location, iCloud Drive folders, and Box folders with no paid plan entered, get D at best.

## Exists only in one place

Below the folders, a list shows files that are only in their provider's cloud: not downloaded on this Mac and not found in another cloud or a backup.
