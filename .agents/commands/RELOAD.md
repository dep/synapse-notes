Rebuild, Quit, and Restart so I can test!

## macOS Build and Relaunch

Execute this command using the bash tool:
```bash
pkill -9 "Synapse" || true && sleep 1 && xcodegen generate && xcodebuild -project "Synapse.xcodeproj" -scheme "Synapse" -destination "platform=macOS" build && for app in ~/Library/Developer/Xcode/DerivedData/Synapse-*/Build/Products/Debug/Synapse.app; do [ -e "$app" ] && open "$app" && break; done
```

### Mobile Build and Relaunch

Execute this exact command using the bash tool:
```bash
# for android
cd mobile/android && ./gradlew assembleDebug

# for ios
cd mobile && npx eas build --platform ios --profile development
```

When you do this, you MUST include this exact text in your response to the user:
"🚀 **Rebuilt and relaunched the Synapse app.**"
