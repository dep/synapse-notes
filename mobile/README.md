# Synapse Mobile

A React Native mobile application built with Expo for the Synapse platform.

## Prerequisites

- Node.js 18+ 
- npm or yarn
- iOS Simulator (macOS with Xcode) or Android Emulator
- Expo Go app (for physical device testing)

## Getting Started

### Installation

```bash
# Install dependencies
npm install
```

### Running the App

```bash
# Start the development server
npm start

# Run on iOS simulator
npm run ios

# Run on Android emulator
npm run android

# Run on web
npm run web
```

## Project Structure

```
mobile/
├── src/
│   ├── components/     # Reusable UI components
│   ├── screens/        # Screen components
│   │   ├── HomeScreen.tsx
│   │   ├── EditorScreen.tsx       # Note editor with history & search
│   │   ├── SettingsScreen.tsx
│   │   ├── OnboardingScreen.tsx
│   │   └── CloneRepositoryScreen.tsx
│   ├── navigation/     # Navigation configuration
│   │   └── AppNavigator.tsx
│   ├── services/       # API and external service integrations
│   │   ├── gitService.ts           # Git operations including history
│   │   └── onboardingStorage.ts
│   ├── hooks/          # Custom React hooks
│   └── theme/          # Theme and styling
│       └── ThemeContext.tsx
├── App.tsx             # Main application entry point
└── package.json
```

## Features

### Navigation
- React Navigation with stack navigator
- Type-safe navigation configuration
- Screen transitions and header customization

### Theming
- Light and dark theme support
- Automatic system preference detection
- Manual theme toggle capability
- Theme-aware components throughout the app

### Onboarding
- First-time user onboarding screen
- Options to create a new workspace or clone a repository
- Persistent onboarding state using AsyncStorage
- Shown only on first app launch (unless state is cleared)

### Search
- **In-file Search**: Search within the currently open note
  - Accessible from search icon in editor toolbar
  - Real-time highlighting of matches as you type
  - Match counter showing current/total matches (e.g., "2 of 12")
  - Previous/next navigation buttons to jump between matches
  - Case-insensitive search
  - Close button or back gesture to dismiss
  
- **Vault-wide Search**: Search across all notes in the repository
  - Accessible from file drawer search bar
  - Real-time search results with 300ms debounce
  - Shows file name, line number, and matching line preview
  - Tappable results to open the file
  - Matches light/dark theme automatically

### Version History
- **View History**: Browse and restore previous versions of your notes
  - History button appears in editor header when file has git commits
  - Shows list of commits with message and date
  - Preview any historical version with syntax-highlighted markdown
  - Restore button replaces current content with selected version
  - File is marked with unsaved changes after restore, ready to save/commit

### Dependencies
- **Expo SDK 55**: Latest stable Expo framework
- **React Navigation**: Navigation library for React Native
- **isomorphic-git**: Git operations in JavaScript
- **@isomorphic-git/lightning-fs**: File system for isomorphic-git
- **react-native-markdown-display**: Markdown rendering
- **@react-native-async-storage/async-storage**: Local storage for persistence

## Development

### TypeScript
The project is configured with TypeScript for type safety. All source files should have `.tsx` extension for components and `.ts` for utilities.

### Theme Usage

```typescript
import { useTheme } from './src/theme/ThemeContext';

function MyComponent() {
  const { theme, isDark, toggleTheme, followSystem, setFollowSystem } = useTheme();
  
  return (
    <View style={{ backgroundColor: theme.colors.background }}>
      <Text style={{ color: theme.colors.text }}>Hello World</Text>
    </View>
  );
}
```

### Navigation

```typescript
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';

type MyScreenProps = NativeStackScreenProps<RootStackParamList, 'Home'>;

export function MyScreen({ navigation }: MyScreenProps) {
  return (
    <Button onPress={() => navigation.navigate('Settings')} />
  );
}
```

### Onboarding Storage

The onboarding state is persisted using AsyncStorage. You can check or reset the onboarding state:

```typescript
import { OnboardingStorage } from './src/services/onboardingStorage';

// Check if user has completed onboarding
const hasCompleted = await OnboardingStorage.hasCompletedOnboarding();

// Mark onboarding as completed
await OnboardingStorage.setOnboardingCompleted();

// Clear onboarding state (for testing)
await OnboardingStorage.clearOnboardingState();
```

## Testing

```bash
# Run tests
npm test

# Run linting
npm run lint
```

## Building

### Production Builds

```bash
# Build for iOS
expo build:ios

# Build for Android
expo build:android
```

## Contributing

1. Create a feature branch from `main`
2. Make your changes
3. Test on both iOS and Android
4. Submit a pull request

## Troubleshooting

### Metro bundler issues
```bash
# Clear cache
npx expo start --clear
```

### iOS build issues
```bash
# Clean build
cd ios && xcodebuild clean
```

### Android build issues
```bash
# Clean and rebuild
cd android && ./gradlew clean
```

## License

MIT
