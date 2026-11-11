# Cloudpane privacy policy

Last updated: November 11, 2026

Cloudpane is a Mac app, made by 404 Cybersecurity LLC, that shows how you use cloud storage.
This policy explains what happens to your information when you use it. The short version:
we don't collect any of it, and Cloudpane never connects to the internet.

## What we collect

Nothing. Cloudpane has no account and no sign-up. It contains no analytics, no crash
reporting, no advertising and no third-party code, and it makes no network connections.
There is no Cloudpane server, so there is nowhere for your data to be sent to us.

## What Cloudpane reads

Only the folders you choose, and only read-only: the folders where your cloud storage apps
keep their files, any backup location you add, and, if you choose it, your Photos library.
Cloudpane reads file names, sizes, dates and types. It reads a file's contents only when you
turn on hashing for a folder to find exact duplicates, and it tells you first if that will
download files from the cloud. It never reads your photos, mail or messages, and it never
asks for your Apple Account or any other login.

Cloudpane itself never goes online, but your cloud storage apps do. When Cloudpane reads a
folder that one of them has not listed on your Mac yet, that app fetches the folder's list
of files from its service, as it does when you open the folder in Finder. It may then
download some files it keeps on your Mac by its own settings. That traffic is between the
app and its service; none of it comes to us.

## What stays on your Mac

What Cloudpane finds and the plans you enter are kept in a database inside the app's own
storage on your Mac, with your settings beside it. Exports and reports are saved to your
Downloads folder only when you ask for one. Moving the app to the Trash does not remove its
database; to remove it, quit Cloudpane and delete the folder
`~/Library/Containers/com.404tools.cloudpane`.

## Crash reports

Cloudpane sends no crash reports, and we receive none. If Cloudpane crashes, macOS may keep
a report on your Mac, where you can read it in the Console app. It reaches us only if you
choose to attach it to a bug report.

## Updates

Cloudpane never checks for updates, because it cannot go online. You get a new version by
downloading it from the releases page on GitHub or by running `brew upgrade --cask cloudpane`
if you installed it with Homebrew. Those downloads come from GitHub, which has its own
privacy policy.

## Children

Cloudpane doesn't collect information from anyone, including children under 13.

## Changes to this policy

If this policy changes, the new version will be posted on this page with a new date. Because
we collect no data, a change can't apply to data we already have; there isn't any.

## Contact

Questions about this policy: open an issue at https://github.com/breed007/Cloudpane/issues
or see https://404tools.app/cloudpane.
