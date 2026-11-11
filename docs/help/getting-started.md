---
title: Getting started
order: 1
platforms: macOS, iOS
summary: What Cloudpane reads, what each provider needs, and the first scan.
---
# Getting started

Cloudpane shows what you keep with iCloud Drive, Dropbox, Google Drive, OneDrive and Box, using the folders each provider's app already keeps on your Mac. It needs no logins. A file kept only in the cloud still leaves a placeholder on the Mac with its name, size and dates, so Cloudpane can count it without downloading it.

## What each provider needs

Cloudpane sees a provider only when its app is installed and signed in on the Mac you scan. A service you use only in a web browser or on another device does not appear.

| Provider | What must be set up |
| --- | --- |
| iCloud Drive | Turned on in System Settings, under your name, then iCloud. It is a system setting, not an app. |
| Dropbox | The Dropbox desktop app, signed in, using the `~/Library/CloudStorage` location. Older installs that keep files in `~/Dropbox` are not seen. |
| Google Drive | Google Drive for desktop, signed in. |
| OneDrive | The OneDrive app, signed in. Each account gets its own folder. |
| Box | Box Drive, signed in. |

<!-- macOS -->
## The two folders

On first launch Cloudpane asks for two folders, one at a time, through the standard open panel:

- `~/Library/CloudStorage`, where most provider apps keep their files, one folder per account.
- `~/Library/Mobile Documents/com~apple~CloudDocs`, the iCloud Drive folder.

Click Grant access beside each one, then Grant access in the panel. Access is read-only, and Cloudpane asks for nothing else in your Library. A folder that is not on this Mac can be skipped. You can grant it later in Settings, which also has Reset folder access.

## The first scan

Click Scan now. The first scan can take a few minutes while each provider's app sends the lists of folders it has not shown on this Mac yet; the progress line then reads "Getting the folder list from" and the provider's name. When it finishes, click Show my footprint to open [Overview](overview.md).

After that, Cloudpane scans when it opens (you can turn this off in Settings) and watches the folders for changes. See [History and live updates](history.md).
<!-- /macOS -->

## Next

- [Overview](overview.md) explains the totals.
- [Privacy](privacy.md) lists what Cloudpane never does.
