import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  ScrollView,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import { useTheme } from '../theme/ThemeContext';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';
import { GitService, GitError } from '../services/gitService';
import { OnboardingStorage } from '../services/onboardingStorage';
import git from 'isomorphic-git';
import * as FileSystem from 'expo-file-system/legacy';

type CloneRepositoryScreenProps = NativeStackScreenProps<RootStackParamList, 'CloneRepository'>;

// Use the document directory for the vault
const getVaultRootPath = () => {
  const docDir = FileSystem.documentDirectory || 'file:///';
  // Android returns 'file:/data/user/...' which is malformed
  // We need 'file:///data/user/...' with three slashes after file:
  const fixedDir = docDir.replace(/^file:\/([^\/])/, 'file:///$1');
  // Ensure it ends with exactly one slash
  const normalizedDir = fixedDir.replace(/\/+$/, '') + '/';
  return `${normalizedDir}vault`;
};

const getRepositoryDirectoryName = (url: string) => {
  const normalizedUrl = url.trim().replace(/\.git$/, '').replace(/\/+$/, '');
  const repoName = normalizedUrl.split(/[/:]/).pop() || 'repository';
  return repoName.replace(/[^A-Za-z0-9._-]/g, '-');
};

const getRepositoryPath = (url: string) => {
  return `${getVaultRootPath()}/${getRepositoryDirectoryName(url)}`;
};

export function CloneRepositoryScreen({ navigation }: CloneRepositoryScreenProps) {
  const { theme } = useTheme();
  const [repoUrl, setRepoUrl] = useState(__DEV__ ? 'https://github.com/dep/notes' : '');
  const [isCloning, setIsCloning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [progress, setProgress] = useState<string>('');

  const validateRepoUrl = (url: string): boolean => {
    // Support both HTTPS and SSH GitHub URLs
    const httpsPattern = /^https:\/\/github\.com\/[^\/]+\/[^\/]+(\/)?$/;
    const sshPattern = /^git@github\.com:[^\/]+\/[^\/]+(\.git)?$/;
    return httpsPattern.test(url) || sshPattern.test(url);
  };

  const handleClone = async () => {
    if (!repoUrl.trim()) {
      setError('Please enter a repository URL');
      return;
    }

    if (!validateRepoUrl(repoUrl.trim())) {
      setError('Invalid GitHub repository URL. Expected format: https://github.com/username/repo');
      return;
    }

    setIsCloning(true);
    setError(null);
    setProgress('Starting clone...');

    try {
      // Get the stored token
      const credentials = await GitService.getCredentials('default');
      
      if (!credentials) {
        setError('No GitHub token found. Please go back and enter your token.');
        setIsCloning(false);
        return;
      }

      const vaultRootPath = getVaultRootPath();
      const cleanUrl = repoUrl.trim().replace(/\.git$/, '');
      const repositoryPath = getRepositoryPath(cleanUrl);
      
      // Ensure the vault root exists
      try {
        const dirInfo = await FileSystem.getInfoAsync(vaultRootPath);
        if (!dirInfo.exists) {
          await FileSystem.makeDirectoryAsync(vaultRootPath, { intermediates: true });
        }
      } catch (dirError) {
        console.log('Vault directory may already exist:', dirError);
      }

      const repoInfo = await FileSystem.getInfoAsync(repositoryPath);
      if (repoInfo.exists) {
        const gitConfigInfo = await FileSystem.getInfoAsync(`${repositoryPath}/.git/config`);

        if (gitConfigInfo.exists) {
          await OnboardingStorage.setActiveRepositoryPath(repositoryPath);
          await OnboardingStorage.setOnboardingCompleted();
          navigation.navigate('Home');
          return;
        }

        await FileSystem.deleteAsync(repositoryPath, { idempotent: true });
      }

      // Update credentials for this specific repo
      await GitService.setCredentials(cleanUrl, credentials.username, credentials.token);

      // Clone the repository
      await GitService.clone(
        cleanUrl,
        repositoryPath,
        (stage: git.ProgressStage) => {
          setProgress(`${stage.phase}: ${stage.loaded}/${stage.total || '?'} ${stage.lengthComputable ? '' : 'objects'}`);
        }
      );

      setProgress('Clone complete!');
      await OnboardingStorage.setActiveRepositoryPath(repositoryPath);
      
      // Mark onboarding as completed
      await OnboardingStorage.setOnboardingCompleted();
      
      // Navigate to home
      navigation.navigate('Home');
    } catch (err) {
      console.error('Clone failed:', err);
      
      if (err instanceof GitError) {
        switch (err.type) {
          case 'AUTH_FAILURE':
            setError('Authentication failed. Please check your GitHub token and ensure it has the "repo" scope.');
            break;
          case 'NETWORK_ERROR':
            setError('Network error. Please check your internet connection and try again.');
            break;
          case 'NOT_A_REPOSITORY':
            setError('The URL does not point to a valid Git repository.');
            break;
          default:
            setError(`Clone failed: ${err.message}`);
        }
      } else {
        setError(`Clone failed: ${err instanceof Error ? err.message : 'Unknown error'}`);
      }
    } finally {
      setIsCloning(false);
    }
  };

  const handleSkip = async () => {
    Alert.alert(
      'Skip Cloning?',
      'You can clone a repository later from the settings.',
      [
        {
          text: 'Cancel',
          style: 'cancel',
        },
        {
          text: 'Skip',
          style: 'default',
          onPress: async () => {
            await OnboardingStorage.setOnboardingCompleted();
            navigation.navigate('Home');
          },
        },
      ]
    );
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.colors.background }]} edges={['top', 'left', 'right']}>
      <ScrollView
        style={styles.container}
        contentContainerStyle={styles.contentContainer}
      >
        <View style={styles.header}>
          <Text style={[styles.title, { color: theme.colors.text }]}>
            Clone Repository
          </Text>
          <Text style={[styles.subtitle, { color: theme.colors.text }]}>
            Enter the GitHub repository URL you want to sync
          </Text>
        </View>

        {/* URL Input */}
        <View style={styles.inputSection}>
          <Text style={[styles.inputLabel, { color: theme.colors.text }]}>
            Repository URL
          </Text>
          <TextInput
            style={[
              styles.input,
              {
                backgroundColor: theme.colors.card,
                color: theme.colors.text,
                borderColor: error ? theme.colors.error : theme.colors.border,
              },
            ]}
            value={repoUrl}
            onChangeText={(text) => {
              setRepoUrl(text);
              setError(null);
            }}
            placeholder="https://github.com/username/repository"
            placeholderTextColor={theme.colors.text + '60'}
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="url"
            editable={!isCloning}
            testID="repo-url-input"
          />
          {error && (
            <Text style={[styles.errorText, { color: theme.colors.error }]}>
              {error}
            </Text>
          )}
        </View>

        {/* Example URLs */}
        <View style={[styles.infoCard, { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 3 }]}>
          <Text style={[styles.infoTitle, { color: theme.colors.text }]}>
            Supported Formats
          </Text>
          <View style={styles.exampleItem}>
            <MaterialIcons name="link" size={16} color={theme.colors.primary} style={{ marginRight: 8 }} />
            <Text style={[styles.infoText, { color: theme.colors.text }]}>https://github.com/user/repo</Text>
          </View>
          <View style={styles.exampleItem}>
            <MaterialIcons name="terminal" size={16} color={theme.colors.primary} style={{ marginRight: 8 }} />
            <Text style={[styles.infoText, { color: theme.colors.text }]}>git@github.com:user/repo.git</Text>
          </View>
        </View>

        {/* Progress */}
        {isCloning && (
          <View style={styles.progressContainer}>
            <ActivityIndicator size="large" color={theme.colors.primary} />
            <Text style={[styles.progressText, { color: theme.colors.text }]}>
              {progress}
            </Text>
          </View>
        )}

        {/* Action Buttons */}
        <View style={styles.buttonContainer}>
          <TouchableOpacity
            style={[
              styles.button,
              { backgroundColor: theme.colors.primary },
              (isCloning || !repoUrl.trim()) && { opacity: 0.6 },
            ]}
            onPress={handleClone}
            disabled={isCloning || !repoUrl.trim()}
            testID="clone-button"
          >
            {isCloning ? (
              <ActivityIndicator size="small" color={theme.colors.background} />
            ) : (
              <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                <MaterialIcons name="file-download" size={20} color={theme.colors.background} style={{ marginRight: 8 }} />
                <Text style={[styles.buttonText, { color: theme.colors.background }]}>
                  Clone Repository
                </Text>
              </View>
            )}
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.skipButton}
            onPress={handleSkip}
            disabled={isCloning}
          >
            <Text style={[styles.skipText, { color: theme.colors.text + '80' }]}>
              Skip for now
            </Text>
          </TouchableOpacity>
        </View>

        {/* Privacy Note */}
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', marginTop: 24 }}>
          <MaterialIcons name="lock" size={14} color={theme.colors.text + '60'} style={{ marginRight: 4 }} />
          <Text style={[styles.privacyNote, { color: theme.colors.text + '60' }]}>
            The repository will be stored locally on your device.
          </Text>
        </View>
      </ScrollView>
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
    marginBottom: 32,
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
  inputSection: {
    marginBottom: 16,
  },
  inputLabel: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 8,
  },
  input: {
    height: 50,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 16,
    fontSize: 16,
  },
  errorText: {
    fontSize: 14,
    marginTop: 8,
  },
  infoCard: {
    padding: 16,
    borderRadius: 12,
    marginBottom: 24,
  },
  infoTitle: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 8,
  },
  infoText: {
    fontSize: 13,
    lineHeight: 20,
    opacity: 0.8,
    fontFamily: 'monospace',
  },
  progressContainer: {
    alignItems: 'center',
    marginVertical: 24,
  },
  progressText: {
    fontSize: 14,
    marginTop: 12,
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
  privacyNote: {
    fontSize: 12,
    textAlign: 'center',
    marginTop: 24,
  },
});
