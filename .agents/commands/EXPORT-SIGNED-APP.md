# Export Signed App

## Description

Export a signed and notarized macOS app for distribution.

## Prerequisites

- A valid `Developer ID Application` certificate with private key installed in your login keychain
- A configured `notarytool` keychain profile named `notarytool` (see Setup below)
- `project.yml` must remain the source of truth for release signing settings
- `create-dmg` installed: `brew install create-dmg`

## Setup: Store Notarization Credentials

`APPLE_EMAIL` and `APPLE_APP_PASSWORD` are in the project's `.env` file. Run this once to store them in the keychain:

```bash
source .env && xcrun notarytool store-credentials "notarytool" \
  --apple-id "$APPLE_EMAIL" \
  --team-id "299R8V27FZ" \
  --password "$APPLE_APP_PASSWORD"
```

## Step-by-Step

### 0. Update the project's version number, incrementing the patch version unless told it's a minor or major release.

```bash
# in macOS/<AppName>/Info.plist
<key>CFBundleShortVersionString</key>
<string>x.y.z</string>
```

### 1. Create a signed Release archive

```bash
xcodegen generate && \
xcodebuild archive \
  -project "<AppName>.xcodeproj" \
  -scheme "<AppName>" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "/tmp/<AppName>.xcarchive"
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
  -archivePath /tmp/<AppName>.xcarchive \
  -exportPath /tmp/<AppName>-export \
  -exportOptionsPlist /tmp/export-options.plist
```

### 3. Submit, wait, and staple

> **Note:** `notarytool` requires a zip/pkg/dmg — it rejects a bare `.app`. Zip first, submit the zip, then staple the `.app`.

```bash
ditto -c -k --keepParent /tmp/<AppName>-export/<AppName>.app /tmp/<AppName>-export/<AppName>.zip && \
xcrun notarytool submit /tmp/<AppName>-export/<AppName>.zip \
  --keychain-profile "notarytool" \
  --wait && \
xcrun stapler staple /tmp/<AppName>-export/<AppName>.app && \
spctl --assess --type execute --verbose /tmp/<AppName>-export/<AppName>.app
```

### 4. Package as DMG for distribution

```bash
mkdir -p /tmp/<AppName>-dmg-src && \
cp -R /tmp/<AppName>-export/<AppName>.app /tmp/<AppName>-dmg-src/ && \
create-dmg \
  --volname "<AppName>" \
  --volicon "/tmp/<AppName>-dmg-src/<AppName>.app/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 160 \
  --icon "<AppName>.app" 180 170 \
  --hide-extension "<AppName>.app" \
  --app-drop-link 480 170 \
  ~/Desktop/<AppName>-<version>.dmg \
  /tmp/<AppName>-dmg-src/
```

## Expected Output

Successful validation should show:
- `accepted`
- `source=Notarized Developer ID`

## Artifacts

- Notarized app: `/tmp/<AppName>-export/<AppName>.app`
- Shareable DMG: `~/Desktop/<AppName>-<version>.dmg`

## One-Liner

```bash
source .env && \
xcodegen generate && \
xcodebuild archive -project "<AppName>.xcodeproj" -scheme "<AppName>" -configuration Release -destination "generic/platform=macOS" -archivePath "/tmp/<AppName>.xcarchive" && \
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
xcodebuild -exportArchive -archivePath /tmp/<AppName>.xcarchive -exportPath /tmp/<AppName>-export -exportOptionsPlist /tmp/export-options.plist && \
ditto -c -k --keepParent /tmp/<AppName>-export/<AppName>.app /tmp/<AppName>-export/<AppName>.zip && \
xcrun notarytool submit /tmp/<AppName>-export/<AppName>.zip --keychain-profile "notarytool" --wait && \
xcrun stapler staple /tmp/<AppName>-export/<AppName>.app && \
spctl --assess --type execute --verbose /tmp/<AppName>-export/<AppName>.app && \
mkdir -p /tmp/<AppName>-dmg-src && cp -R /tmp/<AppName>-export/<AppName>.app /tmp/<AppName>-dmg-src/ && \
create-dmg --volname "<AppName>" --volicon "/tmp/<AppName>-dmg-src/<AppName>.app/Contents/Resources/AppIcon.icns" --window-pos 200 120 --window-size 660 400 --icon-size 160 --icon "<AppName>.app" 180 170 --hide-extension "<AppName>.app" --app-drop-link 480 170 ~/Desktop/<AppName>-<version>.dmg /tmp/<AppName>-dmg-src/
```

### 5. Commit and push the version bump

```bash
git commit -m "bump version to <version>"
git push
```

### 6. Create a release on GitHub

Use what you know about changes SINCE THE LAST RELEASE to generate the release notes.

```bash
gh release create <version> --title "<version>" --notes "<dynamically generated release notes>"
```

Attach the DMG to the release.

```bash
gh release upload <version> ~/Desktop/<AppName>-<version>.dmg
```

> **Note:** GitHub rewrites spaces in uploaded asset filenames to dots. Confirm
> the resolved URL before writing the appcast — it usually becomes
> `<AppName-with-dots>-<version>.dmg`:
>
> ```bash
> gh release view <version> --json assets -q '.assets[] | "\(.name) \(.size) \(.url)"'
> ```

### 7. Sign the DMG for Sparkle and update `appcast.xml`

Sparkle clients verify each release with an EdDSA signature over the DMG.
Generate the signature with the `sign_update` tool that ships with the
Sparkle SwiftPM artifact, then prepend a new `<item>` to the top of
`appcast.xml`.

```bash
SIGN_TOOL=$(find ~/Library/Developer/Xcode/DerivedData -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update' | head -1)
"$SIGN_TOOL" ~/Desktop/<AppName>-<version>.dmg
```

That prints `sparkle:edSignature="…" length=…`. Plug those — along with the
asset URL from step 6, the new `CFBundleVersion` build number, the
`CFBundleShortVersionString`, and an RFC 822 UTC `pubDate`
(`date -u "+%a, %d %b %Y %H:%M:%S +0000"`) — into a new `<item>` at the
top of `appcast.xml`:

```xml
<item>
  <title>Version <version></title>
  <pubDate><RFC 822 UTC date></pubDate>
  <sparkle:version><CFBundleVersion></sparkle:version>
  <sparkle:shortVersionString><version></sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
  <description><![CDATA[
    <h3>What's new</h3>
    <ul>
      <li>…release notes…</li>
    </ul>
  ]]></description>
  <enclosure
    url="<asset URL from step 6>"
    sparkle:edSignature="<signature from sign_update>"
    length="<length from sign_update>"
    type="application/x-apple-diskimage"
  />
</item>
```

Then commit and push so the hosted feed
(`https://raw.githubusercontent.com/<owner>/<repo>/main/appcast.xml`)
serves the new version to existing installs:

```bash
git add appcast.xml
git commit -m "chore: update appcast.xml for <version>"
git push
```
