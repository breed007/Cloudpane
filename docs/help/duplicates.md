---
title: Duplicates
order: 4
platforms: macOS, iOS
summary: How Cloudpane finds copies, and what hashing reads and downloads.
---
# Duplicates

Duplicates groups files in your cloud folders that look like copies of each other, so you can see how much space the extra copies take. Cloudpane never removes or merges anything; each group is for you to review.

## The three tiers

| Tier | What has to match |
| --- | --- |
| Exact | The same SHA-256 hash. Both files were read and hashed. |
| Strong | The same size, the same name, and modification dates within 2 seconds of each other. |
| Weak | The same size only, for files of at least 1 MB (1,000,000 bytes). |

A file appears in its highest tier only. Groups are ranked by how much could be reclaimed: every copy after the first, times the size. The view lists the 500 groups with the most to reclaim, and the totals count every group.

Copies in backup locations are shown under exact and strong groups as "Also in backups, not counted". A copy in a backup is the backup doing its job, so it never counts as space to reclaim. An app or other package counts as one file, and can be a strong or weak duplicate but not an exact one.

## Hashing

Exact matches need each file's contents, which is the only time Cloudpane reads what is inside a file. Hashing is off until you turn it on for a folder.

<!-- macOS -->
Open a provider from Overview, select a top-level folder, and choose Hash this folder. A sheet shows how many files and bytes are only in the cloud and will download to be read, and how many are already on this Mac and are read without downloading. Nothing happens until you confirm.

After that, new or changed files already on this Mac in that folder are hashed automatically. Files that are only in the cloud are hashed only when you choose Hash this folder again and confirm. Settings lists the hashed folders, with Stop hashing this folder for each.
<!-- /macOS -->

<!-- macOS -->
Downloaded files take space on this Mac until macOS removes the local copies again, which it does when it needs the space or when you choose Remove Download.
<!-- /macOS -->

Hashes also confirm backup copies for the [Backup grade](backup-grade.md).

## Placeholders

A placeholder is a file that is only in the cloud: the provider keeps its name, size and dates on the Mac, but not its data. Cloudpane treats a file as a placeholder when macOS marks it as having no local data, or when it reports a size but takes no space on disk and is not marked as downloaded. A compressed file can take no space on disk too; it is not counted as a placeholder.
