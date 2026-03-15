import { StatusBar } from 'expo-status-bar';
import React from 'react';
import { ShareIntentProvider } from 'expo-share-intent';
import { ThemeProvider } from './src/theme/ThemeContext';
import { AppNavigator } from './src/navigation/AppNavigator';

export default function App() {
  return (
    <ShareIntentProvider
      options={{
        debug: __DEV__,
        resetOnBackground: false,
      }}
    >
      <ThemeProvider>
        <AppNavigator />
        <StatusBar style="auto" />
      </ThemeProvider>
    </ShareIntentProvider>
  );
}
