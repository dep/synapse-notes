import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import { useTheme } from '../theme/ThemeContext';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';

type OnboardingScreenProps = NativeStackScreenProps<RootStackParamList, 'Onboarding'>;

export function OnboardingScreen({ navigation }: OnboardingScreenProps) {
  const { theme } = useTheme();

  const handleNewWorkspace = async () => {
    navigation.navigate('GitHubToken', { nextStep: 'Home' });
  };

  const handleCloneRepository = async () => {
    navigation.navigate('GitHubToken', { nextStep: 'CloneRepository' });
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.colors.background }]}>
      <View style={styles.content}>
        <View style={styles.iconContainer}>
          <MaterialIcons name="auto-awesome" size={80} color={theme.colors.primary} />
        </View>

        <Text style={[styles.title, { color: theme.colors.text }]}>
          Welcome to Synapse
        </Text>
        
        <Text style={[styles.subtitle, { color: theme.colors.text }]}>
          Your seamless mobile workspace for thoughts and code
        </Text>

        <View style={styles.buttonContainer}>
          <TouchableOpacity
            style={[styles.button, { backgroundColor: theme.colors.primary }]}
            onPress={handleNewWorkspace}
            testID="new-workspace-button"
          >
            <MaterialIcons name="add-box" size={20} color={theme.colors.background} style={{ marginRight: 8 }} />
            <Text style={[styles.buttonText, { color: theme.colors.background }]}>
              New Workspace
            </Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.button, { backgroundColor: theme.colors.secondary }]}
            onPress={handleCloneRepository}
            testID="clone-repository-button"
          >
            <MaterialIcons name="cloud-download" size={20} color={theme.colors.background} style={{ marginRight: 8 }} />
            <Text style={[styles.buttonText, { color: theme.colors.background }]}>
              Clone Repository
            </Text>
          </TouchableOpacity>
        </View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
  },
  iconContainer: {
    marginBottom: 40,
    padding: 24,
    borderRadius: 40,
    backgroundColor: 'rgba(37, 99, 235, 0.1)',
  },
  title: {
    fontSize: 36,
    fontWeight: '900',
    marginBottom: 12,
    textAlign: 'center',
    letterSpacing: -1,
  },
  subtitle: {
    fontSize: 18,
    marginBottom: 48,
    textAlign: 'center',
    opacity: 0.6,
    lineHeight: 26,
    fontWeight: '400',
  },
  buttonContainer: {
    width: '100%',
    maxWidth: 320,
    gap: 16,
  },
  button: {
    paddingHorizontal: 24,
    paddingVertical: 18,
    borderRadius: 16,
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 4,
  },
  buttonText: {
    fontSize: 18,
    fontWeight: '700',
    letterSpacing: -0.2,
  },
});
