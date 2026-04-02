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
- Sparkle public key: `INY1WwN78I1YxgmJuCDmF+OIDam4jBj5jwBZXkiLFHs=`
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
INY1WwN78I1YxgmJuCDmF+OIDam4jBj5jwBZXkiLFHs=
```

## Per-Release Steps

1. Build the app bundle:

```bash
PORTI_VERSION="0.1.9" \
PORTI_BUILD="1" \
./scripts/package-app.sh
```

2. Put the generated zip into a local release staging folder.
3. Generate Sparkle metadata:

```bash
SPARKLE_BIN_DIR="$HOME/tools/Sparkle/bin" \
./scripts/generate-appcast.sh /path/to/release-staging
```

4. Upload the release zip to GitHub Releases.
5. Upload `appcast.xml` and any related Sparkle artifacts to the same release.
6. Verify the release feed resolves at:

```text
https://github.com/kysz/porti/releases/latest/download/appcast.xml
```

## Current Release Identity

- Bundle identifier: `io.github.kysz.porti`
- Repository: `https://github.com/kysz/porti`
- Sparkle public key: `INY1WwN78I1YxgmJuCDmF+OIDam4jBj5jwBZXkiLFHs=`

## Important Note

Because Porti changed both bundle identifier and Sparkle keypair, treat the first release on this configuration as a manual reinstall break. Existing installs should not be expected to auto-update onto the new line.
