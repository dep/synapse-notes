import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Alert, ActivityIndicator } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import { useTheme } from '../theme/ThemeContext';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';
import { OnboardingStorage } from '../services/onboardingStorage';
import * as FileSystem from 'expo-file-system/legacy';

type SettingsScreenProps = NativeStackScreenProps<RootStackParamList, 'Settings'>;

export function SettingsScreen({ navigation }: SettingsScreenProps) {
  const { theme, isDark, toggleTheme, followSystem, setFollowSystem } = useTheme();
  const [repoPath, setRepoPath] = useState<string | null>(null);
  const [isRemoving, setIsRemoving] = useState(false);

  useEffect(() => {
    OnboardingStorage.getActiveRepositoryPath().then(setRepoPath);
  }, []);

  const repoName = repoPath
    ? repoPath.replace(/\/+$/, '').split('/').pop() || repoPath
    : null;

  const handleRemoveRepo = () => {
    Alert.alert(
      'Remove Repository',
      `Remove "${repoName}" from this device? This deletes all local files but won't affect the remote repo.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Remove',
          style: 'destructive',
          onPress: async () => {
            setIsRemoving(true);
            try {
              if (repoPath) {
                await FileSystem.deleteAsync(repoPath, { idempotent: true });
              }
              await OnboardingStorage.clearActiveRepositoryPath();
              await OnboardingStorage.clearOnboardingState();
              navigation.reset({ index: 0, routes: [{ name: 'Onboarding' }] });
            } catch (e) {
              Alert.alert('Error', 'Failed to remove repository: ' + (e as Error).message);
            } finally {
              setIsRemoving(false);
            }
          },
        },
      ]
    );
  };

  const handleResetOnboarding = async () => {
    await OnboardingStorage.clearOnboardingState();
    navigation.navigate('Onboarding');
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.colors.background }]} edges={['top', 'left', 'right']}>
      {/* Header */}
      <View style={[styles.header, { borderBottomColor: theme.colors.border }]}>
        <TouchableOpacity
          style={styles.backButtonHeader}
          onPress={() => navigation.goBack()}
        >
          <MaterialIcons name="arrow-back" size={28} color={theme.colors.primary} />
        </TouchableOpacity>
        <Text style={[styles.headerTitle, { color: theme.colors.text }]}>
          Settings
        </Text>
        <View style={styles.headerSpacer} />
      </View>

      <ScrollView
        style={styles.container}
        contentContainerStyle={styles.content}
      >
        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: theme.colors.text }]}>
            Appearance
          </Text>

          <View style={[styles.card, { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 3 }]}>
            <View style={styles.settingRow}>
              <Text style={[styles.settingLabel, { color: theme.colors.text }]}>
                Follow System
              </Text>
              <TouchableOpacity
                style={[
                  styles.toggle,
                  { backgroundColor: followSystem ? theme.colors.primary : theme.colors.border }
                ]}
                onPress={() => setFollowSystem(!followSystem)}
              >
                <Text style={[styles.toggleText, { color: theme.colors.background }]}>
                  {followSystem ? 'ON' : 'OFF'}
                </Text>
              </TouchableOpacity>
            </View>

            <View style={[styles.divider, { backgroundColor: theme.colors.border }]} />

            <View style={styles.settingRow}>
              <Text style={[styles.settingLabel, { color: theme.colors.text }]}>
                Dark Mode
              </Text>
              <Text style={[styles.settingValue, { color: theme.colors.primary }]}>
                {isDark ? 'Enabled' : 'Disabled'}
              </Text>
            </View>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: theme.colors.text }]}>
            About
          </Text>

          <View style={[styles.card, { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 3 }]}>
            <Text style={[styles.infoText, { color: theme.colors.text }]}>
              Synapse Mobile
            </Text>
            <Text style={[styles.infoSubtext, { color: theme.colors.text, opacity: 0.6 }]}>
              Version 1.0.0
            </Text>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: theme.colors.text }]}>
            Repository
          </Text>

          <View style={[styles.card, { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 3 }]}>
            {repoName ? (
              <>
                <Text style={[styles.settingLabel, { color: theme.colors.text }]}>
                  {repoName}
                </Text>
                <Text style={[styles.infoSubtext, { color: theme.colors.text, opacity: 0.5, marginTop: 2, marginBottom: 12 }]} numberOfLines={2}>
                  {repoPath}
                </Text>
                <TouchableOpacity
                  style={[styles.removeButton, { borderColor: theme.colors.error }]}
                  onPress={handleRemoveRepo}
                  disabled={isRemoving}
                >
                  {isRemoving ? (
                    <ActivityIndicator size="small" color={theme.colors.error} />
                  ) : (
                    <Text style={[styles.removeButtonText, { color: theme.colors.error }]}>
                      Remove Repository
                    </Text>
                  )}
                </TouchableOpacity>
              </>
            ) : (
              <>
                <Text style={[styles.infoSubtext, { color: theme.colors.text, opacity: 0.6, marginBottom: 12 }]}>
                  No repository connected
                </Text>
                <TouchableOpacity
                  style={[styles.addButton, { backgroundColor: theme.colors.primary }]}
                  onPress={() => navigation.navigate('CloneRepository')}
                >
                  <MaterialIcons name="cloud-download" size={18} color={theme.colors.background} style={{ marginRight: 8 }} />
                  <Text style={[styles.addButtonText, { color: theme.colors.background }]}>
                    Clone a Repository
                  </Text>
                </TouchableOpacity>
              </>
            )}
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  backButtonHeader: {
    paddingRight: 12,
    marginRight: 4,
  },
  headerTitle: {
    flex: 1,
    fontSize: 20,
    fontWeight: '700',
    textAlign: 'center',
  },
  headerSpacer: {
    width: 44,
  },
  content: {
    padding: 24,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 24,
  },
  section: {
    marginBottom: 32,
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '800',
    marginBottom: 12,
    textTransform: 'uppercase',
    letterSpacing: 1,
    opacity: 0.5,
  },
  card: {
    padding: 20,
    borderRadius: 16,
  },
  settingRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  settingLabel: {
    fontSize: 16,
    fontWeight: '600',
  },
  settingValue: {
    fontSize: 16,
    fontWeight: '700',
  },
  toggle: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 20,
    minWidth: 56,
    alignItems: 'center',
  },
  toggleText: {
    fontSize: 12,
    fontWeight: '700',
  },
  divider: {
    height: 1,
    marginVertical: 16,
  },
  infoText: {
    fontSize: 16,
    fontWeight: '700',
    marginBottom: 4,
  },
  infoSubtext: {
    fontSize: 14,
  },
  removeButton: {
    borderWidth: 1,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
    alignItems: 'center',
    marginTop: 8,
  },
  removeButtonText: {
    fontSize: 15,
    fontWeight: '700',
  },
  addButton: {
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'center',
  },
  addButtonText: {
    fontSize: 15,
    fontWeight: '700',
  },
});
