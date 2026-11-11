# Release checklist

Cloudpane is released on GitHub as a Developer ID signed and notarized app. Run these steps
in order for each version.

## 1. Prepare

- [ ] `MARKETING_VERSION` in `project.yml` is the new version, `xcodegen generate` has been
      run, and `CHANGELOG.md` has an entry for it.
- [ ] If CloudpaneCore changed: `swift test` passes in its repository, the new commit is
      tagged with a plain semantic version (no "v") and pushed, `exactVersion` in
      `project.yml` names that tag, and one build has updated `Package.resolved`.
- [ ] Everything is committed and pushed. The release script refuses to run with
      uncommitted changes to tracked files.

## 2. Build

- [ ] Run `scripts/release.sh`. It runs the tests, archives a universal build, signs it with
      the 404 Cybersecurity LLC Developer ID certificate, checks the result, notarizes and
      staples it, and writes `Cloudpane-<version>.zip`, `Cloudpane-<version>.dmg` and
      `SHA256SUMS.txt` to `dist/`.

`SKIP_NOTARIZE=1 scripts/release.sh` is a dry run: it stops after signing and the checks,
and sends nothing to Apple.

## 3. Verify

The script stops if any of these fails. Read its output anyway.

- [ ] Signature: the first Authority line is
      `Developer ID Application: 404 Cybersecurity LLC (YA83Q8FTH3)`.
- [ ] Entitlements: exactly `app-sandbox`, `files.user-selected.read-only`,
      `files.bookmarks.app-scope` and `files.downloads.read-write`. No network entitlement.
- [ ] Demo mode: the `CloudpaneDemo` count is 0.
- [ ] The hardened runtime flag is set, the architectures are `arm64 x86_64`, and the build
      number is the build time, not 0.
- [ ] After stapling, `spctl` accepts the app and the dmg as notarized.
- [ ] Open the dmg, copy Cloudpane to Applications, launch it and run a scan.

## 4. Publish

- [ ] Tag the commit that was built `v<version>` and push the tag. The script prints the
      commit. The tag never goes on a later commit.
- [ ] Create the GitHub release on that tag with the zip, the dmg and `SHA256SUMS.txt`
      attached. Put the changelog entry and the two SHA-256 lines in the notes:

      gh release create v<version> dist/Cloudpane-<version>.zip dist/Cloudpane-<version>.dmg \
        dist/SHA256SUMS.txt --title "Cloudpane <version>" --notes-file <notes file>

- [ ] Bump the cask in `breed007/homebrew-tap`: the version and the SHA-256 of the file the
      cask downloads. Then run `brew upgrade --cask cloudpane` on a Mac that has it.
- [ ] Update https://404tools.app/cloudpane from `docs/404tools-page.md` if the copy changed.
      The download button points at `releases/latest` and needs no change.

## History

Version 1.0 was first prepared for the Mac App Store in November 2026. It was released on
GitHub instead, and GitHub is where Cloudpane is distributed.
