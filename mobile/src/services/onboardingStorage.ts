import AsyncStorage from '@react-native-async-storage/async-storage';

const ONBOARDING_COMPLETED_KEY = 'onboarding_completed';

export class OnboardingStorage {
  static async hasCompletedOnboarding(): Promise<boolean> {
    const value = await AsyncStorage.getItem(ONBOARDING_COMPLETED_KEY);
    return value === 'true';
  }

  static async setOnboardingCompleted(): Promise<void> {
    await AsyncStorage.setItem(ONBOARDING_COMPLETED_KEY, 'true');
  }

  static async clearOnboardingState(): Promise<void> {
    await AsyncStorage.removeItem(ONBOARDING_COMPLETED_KEY);
  }
}
