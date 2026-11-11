---
title: Privacy
order: 10
platforms: macOS, iOS
summary: What Cloudpane reads, what it keeps, and what it never does.
---
# Privacy

Cloudpane reads file names, sizes, dates and types from the folders you grant, and keeps what it finds in its own database on this Mac.

## What Cloudpane never does

- Write to, move, delete or upload your files. Every folder grant is read-only.
- Read or download a file's contents. Hashing for exact duplicates is the one exception, and only for folders you turn it on for. See [Duplicates](duplicates.md).
- Connect to the network. The app has no permission to make a network connection.
- Ask for an Apple Account or any other login, or use a provider's online service.
- Read Mail or Messages, which need Full Disk Access, or read photos. The Photos estimate adds up file sizes inside the library.
- Collect anything. There are no analytics, crash reporting or third-party code.

## What a provider may do

Reading a folder that a provider has not listed on this Mac yet may make the provider's app fetch that folder's list of files, as it would when you open the folder yourself. Once it knows about the files, a provider may download some that it keeps on the Mac by its own settings. In testing, OneDrive downloaded a small OneNote notebook shortcut this way. Cloudpane did not read that file; OneDrive's own background downloads fetched it.

## Where your data stays

The inventory, your plans and your settings stay in Cloudpane's storage on this Mac. Exports and reports are written only when you ask for one. Nothing is sent anywhere.

<!-- macOS -->
Exports and reports go to your Downloads folder.
<!-- /macOS -->

<!-- macOS -->
Moving the app to the Trash does not remove its database. To remove it, quit Cloudpane and delete `~/Library/Containers/com.404tools.cloudpane`.
<!-- /macOS -->
