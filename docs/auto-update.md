# Auto-Update

Porti uses Sparkle 2 for GitHub-distributed updates.

For the release runbook, key backup steps, and restore commands, see [release-checklist.md](./release-checklist.md).

The current app integrates Sparkle at runtime, but Sparkle is only considered configured when the shipped app bundle contains these `Info.plist` keys:

- `SUFeedURL`
- `SUPublicEDKey`
- `CFBundleVersion`
- `CFBundleShortVersionString`

When those keys are missing, Porti disables update actions and shows a configuration message in Settings. This is expected for local `swift run PortiApp` development runs, because SwiftPM does not produce the final release app bundle metadata by default.

## GitHub Release Layout

- Host versioned archives (`.zip` or `.dmg`) on GitHub Releases
- Host `appcast.xml` as a release asset on GitHub Releases
- Sign update archives with Sparkle's EdDSA key

Recommended URLs:

- appcast: `https://github.com/kysz/porti/releases/latest/download/appcast.xml`
- releases: `https://github.com/kysz/porti/releases`

## One-Time Sparkle Setup

Porti already vendors Sparkle through SwiftPM, so after one package build the
Sparkle tools are available under `.build/artifacts/sparkle/Sparkle/bin`.
Then run:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

This stores the private key in your login keychain and prints the public EdDSA key. Export the private key with `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /secure/path/porti_sparkle_private_key` and keep that file backed up separately.

## Bundle Configuration

Your packaged `Porti.app/Contents/Info.plist` needs values like:

```xml
<key>CFBundleShortVersionString</key>
<string>0.1.14</string>
<key>CFBundleVersion</key>
<string>1</string>
<key>SUFeedURL</key>
<string>https://github.com/kysz/porti/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>1lnMBb7o0WzU8i/RDS+2oLm4G2m3FfCDvy6GpC4Duo0=</string>
```

This repo includes a packaging template and script for that:

- template: `packaging/Porti-Info.plist.template`
- packager: `scripts/package-app.sh`

Example:

```bash
PORTI_VERSION="0.1.14" \
PORTI_BUILD="1" \
./scripts/package-app.sh
```

That script:

1. builds the SwiftPM release target
2. creates `dist/Porti.app`
3. copies `Sparkle.framework` into the bundle
4. writes the release `Info.plist`
5. ad-hoc signs the bundle if `codesign` is available
6. creates `dist/Porti-<version>.zip`

## Publishing a Release

Use the local release artifact as the canonical one:

1. Build `dist/Porti-<version>.zip` locally with `scripts/package-app.sh`.
2. Create the GitHub release from that exact local zip with `gh release create`.
3. Generate `appcast.xml` from that same zip, not from a rebuilt CI artifact.
4. Upload `appcast.xml` to the same release with `gh release upload`.
5. Verify the release asset digest matches the local zip you inspected.
6. Verify `releases/latest/download/appcast.xml` resolves and points at the tagged zip.

## GitHub Actions

This repo includes `.github/workflows/release.yml`.

Current behavior:

- builds `dist/Porti-<version>.zip`
- uploads the zip as a workflow artifact
- creates or updates a GitHub release

The default shipping path is not this workflow. The recommended path is to
publish the locally verified `dist/Porti-<version>.zip`, because that guarantees
the release asset matches the artifact you inspected before upload. Use the
GitHub workflow only when you intentionally want a CI-built artifact.

The workflow intentionally does **not** generate the appcast yet, because Sparkle's `generate_appcast` depends on the private signing key being available in a macOS keychain. Keeping that step manual avoids storing or importing the private key into GitHub Actions until you decide how you want to handle that securely.

This repo now uses `releases/latest/download/appcast.xml` as the public Sparkle feed URL, so GitHub Pages is not required.

## Helper Script

This repo includes `scripts/generate-appcast.sh` as a wrapper around Sparkle's `generate_appcast`.

Example:

```bash
APPCAST_DOWNLOAD_URL_PREFIX="https://github.com/kysz/porti/releases/download/v0.1.14/" \
APPCAST_LINK="https://github.com/kysz/porti" \
./scripts/generate-appcast.sh ./release-updates
```

By default, the script uses `.build/artifacts/sparkle/Sparkle/bin/generate_appcast`. Set `SPARKLE_BIN_DIR` only if you want to override that path.
