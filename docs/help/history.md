---
title: History and live updates
order: 8
platforms: macOS, iOS
summary: Scans over time, live updates from the watcher, and what changed between two scans.
---
# History and live updates

Every scan is kept as a snapshot. A file that has not changed is stored once, so keeping history costs little.

## Full scans and updates

A full scan walks every provider folder and backup location again. Cloudpane runs one when it opens, when you ask for one, and when something calls for it: a provider folder appears or disappears, or you exclude or include an account or name a folder in [Providers](providers.md). A scan asked for while another runs starts as soon as that one ends.

<!-- macOS -->
Scan now in Settings, or ⌘R, asks for a scan. Turn off Scan when Cloudpane opens in Settings to skip the one at launch.
<!-- /macOS -->

<!-- macOS -->
With Watch for changes and update the inventory turned on in Settings, Cloudpane watches the granted folders and backup locations. A couple of seconds after changes stop, it rescans only the folders that changed and records an update. Updates are listed as "(update)" in History. The status line under the sidebar says when the inventory was last updated and whether it is watching.
<!-- /macOS -->

## Totals over time

The chart shows each provider's total across scans. It appears after two complete scans.

## What changed

Pick two scans and choose Compare. Cloudpane lists the files added, removed, changed, and moved or renamed between them, with the bytes involved. A removed file and an added file count as one move when they have the same hash, or the same name, size and a modification date within 2 seconds.

A scan that was stopped or interrupted is kept, but totals over time, the backup grade and months to full use complete scans only.
