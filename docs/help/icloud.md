---
title: iCloud
order: 7
platforms: macOS, iOS
summary: What Cloudpane can and cannot measure of your iCloud storage.
---
# iCloud

iCloud storage holds more than iCloud Drive, and only iCloud Drive has a folder on the Mac. The iCloud section in [Providers](providers.md) lists each part of your iCloud storage and says which figures are measured and which are estimates. It appears when iCloud Drive is on this Mac or you have entered something for iCloud.

## iCloud Drive

Measured by the last complete scan, the same way as every other provider.

## Photos

An estimate from the size of your Photos library on this Mac. Cloudpane adds up the sizes of the files inside the library. It never opens a photo, never reads the library's database, and does not use the Photos framework.

<!-- macOS -->
Click Choose Photos library and pick the library, usually `~/Pictures/Photos Library.photoslibrary`. Measure again updates the estimate; Forget library removes it.
<!-- /macOS -->

If macOS does not let Cloudpane read the library, Providers says "macOS did not let Cloudpane read the size of this library, so there is no Photos estimate." Cloudpane does not ask for more access to get around that; enter your total from System Settings instead, as below.

The estimate can be off in both directions:

- With Optimize Mac Storage turned on in Photos, this Mac keeps smaller versions and the originals stay in iCloud, so iCloud holds more.
- Files in the library that share space on disk (copies made as APFS clones) are counted in full, so the estimate can be larger than the space the library takes on disk.
- A library that does not use iCloud Photos is not in iCloud at all.

The estimate is never added to the plan math.

## Your total

Enter your total iCloud usage from System Settings, under your name, then iCloud. The iCloud plan then uses that figure instead of the scan for used space, room left and the percentage, and growth is hidden while it does. Everything else is the total minus iCloud Drive and the Photos estimate: device backups, Messages, Mail and other apps.

## Not available in this build

- Device backups are stored in your Apple Account, which Cloudpane never signs in to.
- Mail and Messages need Full Disk Access, which Cloudpane does not request.
