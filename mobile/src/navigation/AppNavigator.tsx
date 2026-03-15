import React, { useEffect, useState } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { HomeScreen } from '../screens/HomeScreen';
import { SettingsScreen } from '../screens/SettingsScreen';
import { OnboardingScreen } from '../screens/OnboardingScreen';
import { CloneRepositoryScreen } from '../screens/CloneRepositoryScreen';
import { EditorScreen } from '../screens/EditorScreen';
import { GitHubTokenScreen } from '../screens/GitHubTokenScreen';
import { ShareIntentScreen } from '../screens/ShareIntentScreen';
import { useTheme } from '../theme/ThemeContext';
import { OnboardingStorage } from '../services/onboardingStorage';
import { useShareIntentContext } from 'expo-share-intent';

export type RootStackParamList = {
  Home: { openDrawer?: boolean } | undefined;
  Settings: undefined;
  Onboarding: undefined;
  CloneRepository: undefined;
  Editor: { filePath: string };
  GitHubToken: { nextStep?: string } | undefined;
  ShareIntent: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();

export function AppNavigator() {
  const { theme, isDark } = useTheme();
  const [isLoading, setIsLoading] = useState(true);
  const [hasCompletedOnboarding, setHasCompletedOnboarding] = useState(false);
  const { hasShareIntent } = useShareIntentContext();

  useEffect(() => {
    checkOnboardingStatus();
  }, []);

  const checkOnboardingStatus = async () => {
    try {
      const completed = await OnboardingStorage.hasCompletedOnboarding();
      setHasCompletedOnboarding(completed);
    } catch (error) {
      console.error('Error checking onboarding status:', error);
      setHasCompletedOnboarding(false);
    } finally {
      setIsLoading(false);
    }
  };

  if (isLoading) {
    return null;
  }

  return (
    <NavigationContainer>
      <Stack.Navigator
        screenOptions={{
          headerShown: false,
          headerStyle: {
            backgroundColor: theme.colors.card,
          },
          headerTintColor: theme.colors.text,
          headerTitleStyle: {
            fontWeight: '600',
          },
          contentStyle: {
            backgroundColor: theme.colors.background,
          },
        }}
      >
        {hasShareIntent && hasCompletedOnboarding ? (
          // When the app is opened via share intent, go straight to the share screen
          <Stack.Screen name="ShareIntent" component={ShareIntentScreen} />
        ) : !hasCompletedOnboarding ? (
          <>
            <Stack.Screen
              name="Onboarding"
              component={OnboardingScreen}
              options={{ headerShown: false }}
            />
            <Stack.Screen
              name="GitHubToken"
              component={GitHubTokenScreen}
              options={{ title: 'Connect to GitHub', headerShown: true }}
            />
            <Stack.Screen
              name="Home"
              component={HomeScreen}
              options={{ title: 'Synapse' }}
            />
            <Stack.Screen
              name="CloneRepository"
              component={CloneRepositoryScreen}
              options={{ title: 'Clone Repository' }}
            />
          </>
        ) : (
          <>
            <Stack.Screen
              name="Home"
              component={HomeScreen}
              options={{ title: 'Synapse' }}
            />
            <Stack.Screen
              name="Onboarding"
              component={OnboardingScreen}
              options={{ headerShown: false }}
            />
            <Stack.Screen
              name="GitHubToken"
              component={GitHubTokenScreen}
              options={{ title: 'Connect to GitHub', headerShown: true }}
            />
            <Stack.Screen
              name="CloneRepository"
              component={CloneRepositoryScreen}
              options={{ title: 'Clone Repository' }}
            />
            <Stack.Screen
              name="ShareIntent"
              component={ShareIntentScreen}
            />
          </>
        )}
        <Stack.Screen
          name="Settings"
          component={SettingsScreen}
          options={{ title: 'Settings' }}
        />
        <Stack.Screen
          name="Editor"
          component={EditorScreen}
          options={{ title: 'Editor' }}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
}
