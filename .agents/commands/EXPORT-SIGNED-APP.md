# Export Signed App

## Description

Export a signed and notarized macOS app for distribution.

## Prerequisites

- A valid `Developer ID Application` certificate with private key installed in your login keychain
- A configured `notarytool` keychain profile named `notarytool` (see Setup below)
- `project.yml` must remain the source of truth for release signing settings

## Setup: Store Notarization Credentials

`APPLE_EMAIL` and `APPLE_APP_PASSWORD` are in the project's `.env` file. Run this once to store them in the keychain:

```bash
source .env && xcrun notarytool store-credentials "notarytool" \
  --apple-id "$APPLE_EMAIL" \
  --team-id "299R8V27FZ" \
  --password "$APPLE_APP_PASSWORD"
```

## Step-by-Step

### 1. Create a signed Release archive

```bash
xcodegen generate && \
xcodebuild archive \
  -project "Synapse.xcodeproj" \
  -scheme "Synapse" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "/tmp/Synapse.xcarchive"
```

### 2. Export the signed .app

Create an export options plist:

```bash
cat > /tmp/export-options.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath /tmp/Synapse.xcarchive \
  -exportPath /tmp/Synapse-export \
  -exportOptionsPlist /tmp/export-options.plist
```

### 3. Submit, wait, and staple

> **Note:** `notarytool` requires a zip/pkg/dmg — it rejects a bare `.app`. Zip first, submit the zip, then staple the `.app`.

```bash
ditto -c -k --keepParent /tmp/Synapse-export/Synapse.app /tmp/Synapse-export/Synapse.zip && \
xcrun notarytool submit /tmp/Synapse-export/Synapse.zip \
  --keychain-profile "notarytool" \
  --wait && \
xcrun stapler staple /tmp/Synapse-export/Synapse.app && \
spctl --assess --type execute --verbose /tmp/Synapse-export/Synapse.app
```

### 4. Zip for distribution

```bash
cd /tmp/Synapse-export && zip -r --symlinks ~/Desktop/Synapse-1.0.zip Synapse.app
```

## Expected Output

Successful validation should show:
- `accepted`
- `source=Notarized Developer ID`

## Artifacts

- Notarized app: `/tmp/Synapse-export/Synapse.app`
- Shareable zip: `~/Desktop/Synapse-1.0.zip`

## One-Liner

```bash
source .env && \
xcodegen generate && \
xcodebuild archive -project "Synapse.xcodeproj" -scheme "Synapse" -configuration Release -destination "generic/platform=macOS" -archivePath "/tmp/Synapse.xcarchive" && \
cat > /tmp/export-options.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>automatic</string>
    <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath /tmp/Synapse.xcarchive -exportPath /tmp/Synapse-export -exportOptionsPlist /tmp/export-options.plist && \
ditto -c -k --keepParent /tmp/Synapse-export/Synapse.app /tmp/Synapse-export/Synapse.zip && \
xcrun notarytool submit /tmp/Synapse-export/Synapse.zip --keychain-profile "notarytool" --wait && \
xcrun stapler staple /tmp/Synapse-export/Synapse.app && \
spctl --assess --type execute --verbose /tmp/Synapse-export/Synapse.app && \
cd /tmp/Synapse-export && zip -r --symlinks ~/Desktop/Synapse-1.0.zip Synapse.app
```
