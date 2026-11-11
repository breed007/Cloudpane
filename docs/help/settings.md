---
title: Settings
order: 11
platforms: macOS
summary: Scanning, folder access, hashing, backup locations and exports.
---
# Settings

## Scanning

Shows when the last scan ran, with Scan now or Stop scan. Scan when Cloudpane opens and Watch for changes and update the inventory are both on at first. See [History and live updates](history.md).

## Folder access

The two folders Cloudpane reads, `~/Library/CloudStorage` and the iCloud Drive folder, with Grant access for one that is not granted yet. Reset folder access forgets both and returns to the first-run screens; past scans are kept.

## Hashing

The folders you turned hashing on for, with Stop hashing this folder. See [Duplicates](duplicates.md).

## Backup locations

Add a backup location opens a panel to choose a Time Machine backup, a folder on an external drive, or a NAS share. For Time Machine, choose the latest backup rather than the whole disk. You give it a label, say what kind it is, and whether it is on-site or off-site. A folder inside a provider's synced folder cannot be a backup location. A location whose disk is not connected shows "Not connected, so the next scan leaves it out", and the grade sees no backup there until it is connected again. See [Backup grade](backup-grade.md).

## Export

CSV, JSON and the PDF report. See [Exporting and reports](exporting.md).
