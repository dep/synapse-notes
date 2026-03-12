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
  -project "Noted.xcodeproj" \
  -scheme "Noted" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "/tmp/Noted.xcarchive"
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
  -archivePath /tmp/Noted.xcarchive \
  -exportPath /tmp/Noted-export \
  -exportOptionsPlist /tmp/export-options.plist
```

### 3. Submit, wait, and staple

```bash
xcrun notarytool submit /tmp/Noted-export/Noted.app \
  --keychain-profile "notarytool" \
  --wait && \
xcrun stapler staple /tmp/Noted-export/Noted.app && \
spctl --assess --type execute --verbose /tmp/Noted-export/Noted.app
```

### 4. Zip for distribution

```bash
cd /tmp/Noted-export && zip -r --symlinks ~/Desktop/Noted-1.0.zip Noted.app
```

## Expected Output

Successful validation should show:
- `accepted`
- `source=Notarized Developer ID`

## Artifacts

- Notarized app: `/tmp/Noted-export/Noted.app`
- Shareable zip: `~/Desktop/Noted-1.0.zip`

## One-Liner

```bash
source .env && \
xcodegen generate && \
xcodebuild archive -project "Noted.xcodeproj" -scheme "Noted" -configuration Release -destination "generic/platform=macOS" -archivePath "/tmp/Noted.xcarchive" && \
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
xcodebuild -exportArchive -archivePath /tmp/Noted.xcarchive -exportPath /tmp/Noted-export -exportOptionsPlist /tmp/export-options.plist && \
xcrun notarytool submit /tmp/Noted-export/Noted.app --keychain-profile "notarytool" --wait && \
xcrun stapler staple /tmp/Noted-export/Noted.app && \
spctl --assess --type execute --verbose /tmp/Noted-export/Noted.app && \
cd /tmp/Noted-export && zip -r --symlinks ~/Desktop/Noted-1.0.zip Noted.app
```
