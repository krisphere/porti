# Release Checklist

Use this checklist when shipping a Porti release.

## One-Time Setup

1. Download and unpack a Sparkle release locally.
2. Generate or load the Sparkle keypair:

```bash
cd /path/to/Sparkle
./bin/generate_keys
```

3. Export the private key to a file you control:

```bash
./bin/generate_keys -x /secure/path/porti_sparkle_private_key
```

4. Record these values in your password manager or other secure storage:
- Sparkle public key: `1lnMBb7o0WzU8i/RDS+2oLm4G2m3FfCDvy6GpC4Duo0=`
- Private key export path
- SHA-256 of the exported private key file

Generate the checksum with:

```bash
shasum -a 256 /secure/path/porti_sparkle_private_key
```

5. Copy the private key export to at least one offline or separate backup location.

## Restore On Another Machine

1. Install or unpack the same Sparkle toolset.
2. Import the saved private key:

```bash
cd /path/to/Sparkle
./bin/generate_keys -f /secure/path/porti_sparkle_private_key
```

3. Verify that `./bin/generate_keys` prints the expected public key:

```bash
./bin/generate_keys
```

Expected public key:

```text
1lnMBb7o0WzU8i/RDS+2oLm4G2m3FfCDvy6GpC4Duo0=
```

## Per-Release Steps

Use the local verified artifact as the source of truth. Do not rely on a CI
rebuild for normal releases.

1. Update the version in source and docs first.
2. Build the release bundle locally:

```bash
PORTI_VERSION="0.1.11" \
PORTI_BUILD="0001011" \
./scripts/package-app.sh
```

3. Verify the exact artifact you are about to ship:

```bash
shasum -a 256 dist/Porti-0.1.11.zip
```

4. Commit the release changes and push `main`.
5. Create and push the release tag:

```bash
git tag -a v0.1.11 -m "v0.1.11"
git push origin v0.1.11
```

6. Create the GitHub release from the local zip, not from CI:

```bash
gh release create v0.1.11 \
  dist/Porti-0.1.11.zip \
  --generate-notes \
  --title v0.1.11
```

7. Generate Sparkle metadata from that same local zip:

```bash
rm -rf /tmp/porti-release-feed
mkdir -p /tmp/porti-release-feed
cp dist/Porti-0.1.11.zip /tmp/porti-release-feed/

/path/to/Sparkle/bin/generate_appcast \
  --download-url-prefix https://github.com/kysz/porti/releases/download/v0.1.11/ \
  --link https://github.com/kysz/porti \
  /tmp/porti-release-feed
```

8. Upload `appcast.xml` to the same release:

```bash
gh release upload v0.1.11 /tmp/porti-release-feed/appcast.xml --clobber
```

9. Verify the uploaded release asset still matches the local zip:

```bash
gh release view v0.1.11 --json assets
shasum -a 256 dist/Porti-0.1.11.zip
```

10. Verify the public feed resolves and points at the tagged asset:

```text
https://github.com/kysz/porti/releases/latest/download/appcast.xml
```

11. Only use `.github/workflows/release.yml` when you intentionally want a
CI-built artifact. Do not use it for the default shipping path.

## Current Release Identity

- Bundle identifier: `io.github.kysz.porti`
- Repository: `https://github.com/kysz/porti`
- Sparkle public key: `1lnMBb7o0WzU8i/RDS+2oLm4G2m3FfCDvy6GpC4Duo0=`

## Important Note

Because Porti changed both bundle identifier and Sparkle keypair, treat the first release on this configuration as a manual reinstall break. Existing installs should not be expected to auto-update onto the new line.
