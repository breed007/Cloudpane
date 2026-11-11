---
title: Troubleshooting
order: 12
platforms: macOS, iOS
summary: When a provider is missing, a view is partial, or the numbers look wrong.
---
# Troubleshooting

## A provider does not show up

Its app must be installed and signed in on this Mac, using its current folder in `~/Library/CloudStorage` (iCloud Drive uses its own folder). See [Getting started](getting-started.md). Add provider in [Providers](providers.md) lists what each missing provider needs.

<!-- macOS -->
If the provider is listed as unavailable because Cloudpane has no access, grant the folder in Settings.
<!-- /macOS -->

## Partial view

A provider is a partial view when the last scan could not see some of its folders. The reason names the cause:

- The provider did not provide a folder's list: the folder was still cloud-only after Cloudpane asked for it. Scan again later, when the provider's app is running and online.
- Permission was denied: macOS refused to list the folder.
- A path is too long to read.
- A folder could not be listed for another reason.

When one of several accounts cannot be read, the provider is also a partial view, and the other accounts are still scanned.

## "Getting the folder list from"

The scan is waiting for a provider to send the list of a folder it has not shown on this Mac before. A first scan of a large account can spend most of its time here.

## Counts that differ from a file browser

Cloudpane's file counts and sizes can differ from what a file browser shows:

- An app, a Photos library or another package counts as one item, sized by the files inside it.
- Hidden files and folders are skipped, and so are symbolic links.
- A file with several hard links counts once.
- Sizes are logical sizes, as each provider counts them. A file only in the cloud takes almost no space on disk but counts at its full size.

## The numbers look out of date

<!-- macOS -->
Choose Scan now in Settings or press ⌘R. If Watch for changes is off, Cloudpane only updates on a scan.
<!-- /macOS -->
Plans and the backup grade use the latest complete scan, so a stopped scan does not change them.

<!-- macOS -->
## The window is missing

Choose Window > Cloudpane, press ⌘0, or click Cloudpane in the Dock. Closing the main window quits Cloudpane when no other Cloudpane window, such as Help, is open.

## Starting over with folder access

Settings > Folder access > Reset folder access forgets both folders and returns to the first-run screens. Past scans are kept.
<!-- /macOS -->

## The inventory was written by a newer version

Cloudpane does not open a database written by a newer version, and leaves it as it is. Update Cloudpane to open it.
