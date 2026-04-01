# Auto-Update

Porti uses Sparkle 2 for GitHub-distributed updates.

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

- appcast: `https://github.com/krisphere/porti/releases/latest/download/appcast.xml`
- releases: `https://github.com/krisphere/porti/releases`

## One-Time Sparkle Setup

Download a Sparkle release distribution from the Sparkle project and unpack it locally. Then run:

```bash
./bin/generate_keys
```

This stores the private key in your login keychain and prints the public EdDSA key. Copy the public key into the shipped app bundle's `SUPublicEDKey`.

## Bundle Configuration

Your packaged `Porti.app/Contents/Info.plist` needs values like:

```xml
<key>CFBundleShortVersionString</key>
<string>0.1.2</string>
<key>CFBundleVersion</key>
<string>1</string>
<key>SUFeedURL</key>
<string>https://github.com/krisphere/porti/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>YOUR_BASE64_PUBLIC_KEY</string>
```

This repo includes a packaging template and script for that:

- template: `packaging/Porti-Info.plist.template`
- packager: `scripts/package-app.sh`

Example:

```bash
PORTI_VERSION="0.1.2" \
PORTI_BUILD="1" \
PORTI_SPARKLE_PUBLIC_KEY="YOUR_BASE64_PUBLIC_KEY" \
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

1. Build a new `Porti.app` release bundle with `scripts/package-app.sh`.
2. Place the generated `.zip` archive in a local updates folder.
3. Run `generate_appcast` from the Sparkle distribution against that folder.
4. Upload the archive to GitHub Releases.
5. Upload `appcast.xml` and any delta files as release assets.

## GitHub Actions

This repo includes `.github/workflows/release.yml`.

Current behavior:

- builds `dist/Porti-<version>.zip`
- uploads the zip as a workflow artifact
- creates or updates a GitHub release

Required secret:

- `PORTI_SPARKLE_PUBLIC_KEY`

The workflow intentionally does **not** generate the appcast yet, because Sparkle's `generate_appcast` depends on the private signing key being available in a macOS keychain. Keeping that step manual avoids storing or importing the private key into GitHub Actions until you decide how you want to handle that securely.

This repo now uses `releases/latest/download/appcast.xml` as the public Sparkle feed URL, so GitHub Pages is not required.

## Helper Script

This repo includes `scripts/generate-appcast.sh` as a wrapper around Sparkle's `generate_appcast`.

Example:

```bash
SPARKLE_BIN_DIR="$HOME/tools/Sparkle/bin" \
./scripts/generate-appcast.sh ./release-updates
```

The script expects `generate_appcast` to already be available from an unpacked Sparkle distribution.
