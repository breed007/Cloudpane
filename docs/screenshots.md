# Screenshots

How to take the screenshots for https://404tools.app/cloudpane and the README.

## Rule: invented data only

Screenshots are taken from the demo data, never from a real Mac's folders. Real
screenshots would show account folder names (Google Drive's carries an email address), file
names and the home folder's path. With demo data there is nothing to blur: every account,
folder and file on screen is made up, and the home folder shows as `~`.

The demo data also avoids anything that merely looks like a real person. The Google Drive
account is `you@example.com`, other accounts are named Personal, Home or Northwind
(Microsoft's long-standing fictional sample company), and no file or folder carries a
person's name. Before publishing, check each image for:

- a person's name, email address or username, other than `you@example.com`
- a home-folder path (`/Users/...`) instead of `~`
- the Mac's name, a real network share or a real volume name
- anything from the menu bar or Dock other than Cloudpane, if the capture is not window-only

If a new demo item is added, it follows the same rule.

## Demo data mode (Debug builds only)

`Cloudpane/DemoData.swift` is wrapped in `#if DEBUG`, and so is every line that calls it, so
Release builds contain no demo mode and no way to turn one on. `scripts/release.sh` confirms
this on the signed binary and stops if the demo string is there.

Launched with `-CloudpaneDemo`, a Debug build:

- builds a made-up home folder in the app's temporary folder with all five services, a mix of
  files on the Mac and files only in the cloud, a few duplicates across services, and a
  backup location labeled "Studio NAS";
- uses its own database and its own defaults (`com.404tools.cloudpane.demo`), rebuilt on
  every demo launch, so the real inventory and folder grants are not read or changed;
- turns off open panels, which would otherwise save their last folder in the real defaults,
  and the window's frame autosave. SwiftUI still writes the sidebar's split-view frames to
  the real defaults domain; the demo puts the earlier values back when it quits normally
  (Cloudpane > Quit), but not when it is killed. Before a scripted run, export the real
  preferences (`defaults export ~/Library/Containers/com.404tools.cloudpane/Data/Library/Preferences/com.404tools.cloudpane.plist <copy>`)
  and import them again afterwards;
- records one scan, adds two files, enters four plans (one marked as a Microsoft 365 bundle),
  then scans again on launch, so History has two points;
- skips onboarding and does not watch for changes.

`-CloudpaneDemoHelp <topic>` opens the Help window at a topic, such as `backup-grade` or
`duplicates#hashing`, and `-CloudpaneDemoHelpSearch <words>` types a search into it.
`-CloudpaneDemoSize 1040x700` sizes the window, and `-CloudpaneDemoAddProvider <tab>`
(`supported`, `planOnly` or `nameFolder`) opens Providers' Add provider sheet on that tab.
The demo also has a plan with no folder ("Photo vault"), a named folder ("SyncSpace"), an
unnamed one, and an excluded OneDrive account.

To open a given view at launch, add `-sidebarSelection <view>`, where view is one of
`overview`, `fileSearch`, `duplicates`, `backupGrade`, `providers`, `history`, `settings`.

Growth and months to full stay hidden in the demo: both scans are minutes apart, and growth
needs scans at least a day apart. That is the app working as designed, not a demo bug.

## Size

Use 2560 x 1600 pixels: a window of exactly 1280 x 800 points, captured on a Retina
display. One size for every image keeps the page and the README even.

## Views, in order

1. Overview: totals per service, on this Mac versus only in the cloud.
2. Backup grade: the overall letter, a folder's explanation, and the single-point list.
3. Duplicates: groups ranked by reclaimable space, with a group expanded.
4. Providers: every account with its status and plan, monthly cost, cost per terabyte, the
   bundle total, and the iCloud section.
5. File search: a search that finds the same photo in two services.
6. History: the chart with both scans.

Optional: Settings, showing the read-only folder grants and Export PDF.

## Steps

Run these from the Cloudpane folder. The window ID comes from a short Swift script, because
`screencapture -l` needs one and capturing the whole screen would also capture the desktop.

```sh
# 1. Build Debug.
xcodebuild -project Cloudpane.xcodeproj -scheme Cloudpane -configuration Debug \
  -derivedDataPath build/screens build \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual

# 2. Launch the demo on the first view.
open -n build/screens/Build/Products/Debug/Cloudpane.app --args -CloudpaneDemo -sidebarSelection overview

# 3. Size the window to 1280 x 800 points. Terminal needs Accessibility permission
#    (System Settings > Privacy & Security > Accessibility) for this step.
osascript -e 'tell application "System Events" to tell process "Cloudpane" to set size of window 1 to {1280, 800}'

# 4. Capture the window only, without its shadow.
cat > /tmp/cloudpane-winid.swift <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Cloudpane" && (w[kCGWindowLayer as String] as? Int) == 0 {
    print(w[kCGWindowNumber as String] as! Int); break
}
SWIFT
screencapture -x -o -l "$(swift /tmp/cloudpane-winid.swift)" ~/Desktop/cloudpane-1-overview.png

# 5. Check the size: expect 2560 x 1600.
sips -g pixelWidth -g pixelHeight ~/Desktop/cloudpane-1-overview.png
```

Quit the app and repeat steps 2 to 5 for each view with its `-sidebarSelection` value.
Expanding a duplicate group or typing a search needs a click before step 4. Then check every
image against the list under "Rule: invented data only".

`build/` is ignored by git. The website keeps its own copies of the images. An image shown
in the README goes in `docs/images/`; keep those few and small.
