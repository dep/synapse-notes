import AsyncStorage from '@react-native-async-storage/async-storage';
import { OnboardingStorage } from '../../src/services/onboardingStorage';

// Mock AsyncStorage
jest.mock('@react-native-async-storage/async-storage', () => ({
  setItem: jest.fn(() => Promise.resolve()),
  getItem: jest.fn(() => Promise.resolve(null)),
  removeItem: jest.fn(() => Promise.resolve()),
}));

describe('OnboardingStorage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('hasCompletedOnboarding', () => {
    it('should return false when no onboarding state is stored', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValueOnce(null);

      const result = await OnboardingStorage.hasCompletedOnboarding();

      expect(result).toBe(false);
      expect(AsyncStorage.getItem).toHaveBeenCalledWith('onboarding_completed');
    });

    it('should return true when onboarding is marked as completed', async () => {
      (AsyncStorage.getItem as jest.Mock).mockResolvedValueOnce('true');

      const result = await OnboardingStorage.hasCompletedOnboarding();

      expect(result).toBe(true);
    });
  });

  describe('setOnboardingCompleted', () => {
    it('should persist onboarding completed state', async () => {
      await OnboardingStorage.setOnboardingCompleted();

      expect(AsyncStorage.setItem).toHaveBeenCalledWith('onboarding_completed', 'true');
    });
  });

  describe('clearOnboardingState', () => {
    it('should remove onboarding state from storage', async () => {
      await OnboardingStorage.clearOnboardingState();

      expect(AsyncStorage.removeItem).toHaveBeenCalledWith('onboarding_completed');
    });
  });
});
