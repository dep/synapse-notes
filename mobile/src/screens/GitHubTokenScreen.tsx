import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  ScrollView,
  Linking,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import { useTheme } from '../theme/ThemeContext';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';
import { GitService } from '../services/gitService';
import { OnboardingStorage } from '../services/onboardingStorage';

type GitHubTokenScreenProps = NativeStackScreenProps<RootStackParamList, 'GitHubToken'>;

const GITHUB_TOKEN_URL = 'https://github.com/settings/tokens/new';
const REQUIRED_SCOPES = ['repo', 'read:user'];

export function GitHubTokenScreen({ navigation, route }: GitHubTokenScreenProps) {
  const { theme } = useTheme();
  const [token, setToken] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showToken, setShowToken] = useState(false);

  const { nextStep = 'Home' } = route.params || {};

  const openGitHubTokenPage = async () => {
    try {
      await Linking.openURL(GITHUB_TOKEN_URL);
    } catch (err) {
      console.error('Failed to open URL:', err);
    }
  };

  const validateToken = (token: string): boolean => {
    // GitHub PATs are typically 40 character hex strings (classic) or start with ghp_ (fine-grained)
    if (token.startsWith('ghp_')) {
      return token.length >= 10; // Fine-grained tokens start with ghp_
    }
    // Classic tokens are 40 hex characters
    return /^[a-f0-9]{40}$/i.test(token);
  };

  const handleContinue = async () => {
    if (!token.trim()) {
      setError('Please enter a GitHub Personal Access Token');
      return;
    }

    if (!validateToken(token)) {
      setError('Invalid token format. GitHub tokens should be 40 characters (classic) or start with "ghp_" (fine-grained)');
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      // Store the token with a placeholder URL (will be updated when cloning)
      // For now, we'll store it with a generic key for the user's default credentials
      await GitService.setCredentials('default', 'token', token.trim());

      // Mark onboarding as completed
      await OnboardingStorage.setOnboardingCompleted();

      // Navigate to next step
      if (nextStep === 'CloneRepository') {
        navigation.navigate('CloneRepository');
      } else {
        navigation.navigate('Home');
      }
    } catch (err) {
      console.error('Failed to save token:', err);
      setError('Failed to save token. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleSkip = async () => {
    // Allow skipping but mark onboarding complete
    await OnboardingStorage.setOnboardingCompleted();
    navigation.navigate('Home');
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.colors.background }]} edges={['top', 'left', 'right']}>
      <KeyboardAvoidingView
        style={styles.container}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      >
      <ScrollView
        style={styles.container}
        contentContainerStyle={styles.contentContainer}
        keyboardShouldPersistTaps="handled"
      >
        <View style={styles.header}>
          <Text style={[styles.title, { color: theme.colors.text }]}>
            Connect to GitHub
          </Text>
          <Text style={[styles.subtitle, { color: theme.colors.text }]}>
            To sync your notes with GitHub, you need a Personal Access Token
          </Text>
        </View>

        {/* Info Section */}
        <View style={[styles.infoCard, { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 3 }]}>
          <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 8 }}>
            <MaterialIcons name="info" size={20} color={theme.colors.primary} style={{ marginRight: 8 }} />
            <Text style={[styles.infoTitle, { color: theme.colors.text }]}>
              What's a Personal Access Token?
            </Text>
          </View>
          <Text style={[styles.infoText, { color: theme.colors.text }]}>
            A PAT is like a password that lets Synapse access your GitHub repositories.
            It's more secure than using your actual GitHub password.
          </Text>
        </View>

        {/* Required Scopes */}
        <View style={[styles.scopesCard, { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 3 }]}>
          <Text style={[styles.scopesTitle, { color: theme.colors.text }]}>
            Required Permissions
          </Text>
          <Text style={[styles.scopesDescription, { color: theme.colors.text }]}>
            When creating your token, please enable these scopes:
          </Text>
          {REQUIRED_SCOPES.map((scope) => (
            <View key={scope} style={styles.scopeItem}>
              <MaterialIcons
                name="check-circle"
                size={18}
                color={theme.colors.success}
                style={{ marginRight: 8 }}
              />
              <Text style={[styles.scopeText, { color: theme.colors.text }]}>
                {scope === 'repo' ? 'repo (Full control of private repositories)' :
                 scope === 'read:user' ? 'read:user (Read user profile data)' : scope}
              </Text>
            </View>
          ))}
        </View>

        {/* Token Input */}
        <View style={styles.inputSection}>
          <Text style={[styles.inputLabel, { color: theme.colors.text }]}>
            Your GitHub Personal Access Token
          </Text>
          <View style={styles.inputContainer}>
            <TextInput
              style={[
                styles.input,
                {
                  backgroundColor: theme.colors.card,
                  color: theme.colors.text,
                  borderColor: error ? theme.colors.error : theme.colors.border,
                },
              ]}
              value={token}
              onChangeText={(text) => {
                setToken(text);
                setError(null);
              }}
              placeholder="ghp_xxxxxxxxxxxx or 40-character token"
              placeholderTextColor={theme.colors.text + '60'}
              secureTextEntry={!showToken}
              autoCapitalize="none"
              autoCorrect={false}
              editable={!isLoading}
              testID="token-input"
            />
            <TouchableOpacity
              style={styles.showButton}
              onPress={() => setShowToken(!showToken)}
            >
              <MaterialIcons
                name={showToken ? 'visibility-off' : 'visibility'}
                size={22}
                color={theme.colors.text + '80'}
              />
            </TouchableOpacity>
          </View>
          {error && (
            <Text style={[styles.errorText, { color: theme.colors.error }]}>
              {error}
            </Text>
          )}
        </View>

        {/* Generate Token Link */}
        <TouchableOpacity
          style={styles.linkButton}
          onPress={openGitHubTokenPage}
        >
          <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center' }}>
            <MaterialIcons name="launch" size={18} color={theme.colors.primary} style={{ marginRight: 8 }} />
            <Text style={[styles.linkText, { color: theme.colors.primary }]}>
              Generate a token on GitHub
            </Text>
          </View>
        </TouchableOpacity>

        {/* Action Buttons */}
        <View style={styles.buttonContainer}>
          <TouchableOpacity
            style={[
              styles.button,
              styles.continueButton,
              { backgroundColor: theme.colors.primary },
              (isLoading || !token.trim()) && { opacity: 0.6 },
            ]}
            onPress={handleContinue}
            disabled={isLoading || !token.trim()}
            testID="continue-button"
          >
            {isLoading ? (
              <ActivityIndicator size="small" color={theme.colors.background} />
            ) : (
              <Text style={[styles.buttonText, { color: theme.colors.background }]}>
                Continue
              </Text>
            )}
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.skipButton}
            onPress={handleSkip}
            disabled={isLoading}
          >
            <Text style={[styles.skipText, { color: theme.colors.text + '80' }]}>
              Skip for now
            </Text>
          </TouchableOpacity>
        </View>

        {/* Security Note */}
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', marginTop: 24 }}>
          <MaterialIcons name="lock" size={14} color={theme.colors.text + '60'} style={{ marginRight: 4 }} />
          <Text style={[styles.securityNote, { color: theme.colors.text + '60' }]}>
            Your token is stored securely on your device.
          </Text>
        </View>
      </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  contentContainer: {
    padding: 20,
  },
  header: {
    marginBottom: 24,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 8,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 16,
    textAlign: 'center',
    opacity: 0.7,
  },
  infoCard: {
    padding: 16,
    borderRadius: 12,
    marginBottom: 16,
  },
  infoTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
  },
  infoText: {
    fontSize: 14,
    lineHeight: 20,
    opacity: 0.8,
  },
  scopesCard: {
    padding: 16,
    borderRadius: 12,
    marginBottom: 24,
  },
  scopesTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
  },
  scopesDescription: {
    fontSize: 14,
    marginBottom: 12,
    opacity: 0.8,
  },
  scopeItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  scopeBullet: {
    fontSize: 16,
    marginRight: 8,
    fontWeight: 'bold',
  },
  scopeText: {
    fontSize: 14,
  },
  inputSection: {
    marginBottom: 16,
  },
  inputLabel: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 8,
  },
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  input: {
    flex: 1,
    height: 50,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 16,
    fontSize: 16,
  },
  showButton: {
    position: 'absolute',
    right: 12,
    padding: 8,
  },
  showButtonText: {
    fontSize: 20,
  },
  errorText: {
    fontSize: 14,
    marginTop: 8,
  },
  linkButton: {
    marginBottom: 24,
  },
  linkText: {
    fontSize: 16,
    textAlign: 'center',
    textDecorationLine: 'underline',
  },
  buttonContainer: {
    gap: 12,
  },
  button: {
    paddingHorizontal: 24,
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
  },
  continueButton: {
    minWidth: 200,
  },
  buttonText: {
    fontSize: 18,
    fontWeight: '600',
  },
  skipButton: {
    padding: 12,
    alignItems: 'center',
  },
  skipText: {
    fontSize: 16,
  },
  securityNote: {
    fontSize: 12,
    textAlign: 'center',
    marginTop: 24,
  },
});
