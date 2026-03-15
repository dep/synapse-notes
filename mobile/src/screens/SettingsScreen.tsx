import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Alert, ActivityIndicator, TextInput, KeyboardAvoidingView, Platform } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import { useTheme } from '../theme/ThemeContext';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';
import { OnboardingStorage } from '../services/onboardingStorage';
import { SettingsStorage } from '../services/SettingsStorage';
import { TemplateStorage } from '../services/TemplateStorage';
import * as FileSystem from 'expo-file-system/legacy';

type SettingsScreenProps = NativeStackScreenProps<RootStackParamList, 'Settings'>;

export function SettingsScreen({ navigation }: SettingsScreenProps) {
  const { theme, isDark, toggleTheme, followSystem, setFollowSystem } = useTheme();
  const [repoPath, setRepoPath] = useState<string | null>(null);
  const [isRemoving, setIsRemoving] = useState(false);
  
  // Daily Note settings
  const [dailyNotesEnabled, setDailyNotesEnabled] = useState(false);
  const [dailyNotesOpenOnStartup, setDailyNotesOpenOnStartup] = useState(false);
  const [dailyNotesFolder, setDailyNotesFolder] = useState('daily');
  const [dailyNotesTemplate, setDailyNotesTemplate] = useState('');
  const [isLoadingSettings, setIsLoadingSettings] = useState(true);
  
  // Template settings
  const [templatesDirectory, setTemplatesDirectory] = useState('templates');
  const [availableTemplates, setAvailableTemplates] = useState<string[]>([]);
  
  // File browser settings
  const [fileExtensionFilter, setFileExtensionFilter] = useState('*.md, *.txt');
  const [hiddenFileFolderFilter, setHiddenFileFolderFilter] = useState('');

  useEffect(() => {
    OnboardingStorage.getActiveRepositoryPath().then(path => {
      setRepoPath(path);
      if (path) {
        loadAvailableTemplates(templatesDirectory, path);
      }
    });
    loadDailyNoteSettings();
    loadTemplateSettings();
    loadFileBrowserSettings();
  }, []);

  const loadDailyNoteSettings = async () => {
    setIsLoadingSettings(true);
    try {
      const settings = await SettingsStorage.getAllDailyNoteSettings();
      setDailyNotesEnabled(settings.dailyNotesEnabled);
      setDailyNotesOpenOnStartup(settings.dailyNotesOpenOnStartup);
      setDailyNotesFolder(settings.dailyNotesFolder);
      setDailyNotesTemplate(settings.dailyNotesTemplate);
    } catch (error) {
      console.error('Failed to load daily note settings:', error);
    } finally {
      setIsLoadingSettings(false);
    }
  };

  const handleDailyNotesToggle = async (enabled: boolean) => {
    setDailyNotesEnabled(enabled);
    await SettingsStorage.setDailyNotesEnabled(enabled);
  };

  const handleOpenOnStartupToggle = async (enabled: boolean) => {
    setDailyNotesOpenOnStartup(enabled);
    await SettingsStorage.setDailyNotesOpenOnStartup(enabled);
  };

  const handleFolderChange = async (folder: string) => {
    setDailyNotesFolder(folder);
    await SettingsStorage.setDailyNotesFolder(folder);
  };

  const handleTemplateChange = async (template: string) => {
    setDailyNotesTemplate(template);
    await SettingsStorage.setDailyNotesTemplate(template);
  };

  const loadTemplateSettings = async () => {
    try {
      const dir = await TemplateStorage.getTemplatesDirectory();
      setTemplatesDirectory(dir);
    } catch (error) {
      console.error('Failed to load template settings:', error);
    }
  };

  const handleTemplatesDirectoryChange = async (directory: string) => {
    setTemplatesDirectory(directory);
    await TemplateStorage.setTemplatesDirectory(directory);
    // Reload available templates when directory changes
    if (repoPath) {
      loadAvailableTemplates(directory, repoPath);
    }
  };

  const loadAvailableTemplates = async (templatesDir: string, vaultPath: string) => {
    try {
      await TemplateStorage.setTemplatesDirectory(templatesDir);
      const templates = await TemplateStorage.getAvailableTemplates(vaultPath);
      setAvailableTemplates(templates.map(t => t.name));
    } catch (error) {
      console.error('Failed to load available templates:', error);
      setAvailableTemplates([]);
    }
  };

  // File browser settings handlers
  const loadFileBrowserSettings = async () => {
    try {
      const settings = await SettingsStorage.getAllFileBrowserSettings();
      setFileExtensionFilter(settings.fileExtensionFilter);
      setHiddenFileFolderFilter(settings.hiddenFileFolderFilter);
    } catch (error) {
      console.error('Failed to load file browser settings:', error);
    }
  };

  const handleFileExtensionFilterChange = async (filter: string) => {
    setFileExtensionFilter(filter);
    await SettingsStorage.setFileExtensionFilter(filter);
  };

  const handleHiddenFileFolderFilterChange = async (filter: string) => {
    setHiddenFileFolderFilter(filter);
    await SettingsStorage.setHiddenFileFolderFilter(filter);
  };

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
      <KeyboardAvoidingView
        style={styles.container}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      >
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
        keyboardShouldPersistTaps="handled"
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
            File Browser
          </Text>

          <View style={[styles.card, { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 3 }]}>
            {/* Show Files Matching */}
            <View style={styles.inputRow}>
              <Text style={[styles.inputLabel, { color: theme.colors.text }]}>
                Show Files Matching
              </Text>
              <TextInput
                style={[
                  styles.textInput,
                  {
                    color: theme.colors.text,
                    backgroundColor: theme.colors.background,
                    borderColor: theme.colors.border,
                  },
                ]}
                value={fileExtensionFilter}
                onChangeText={handleFileExtensionFilterChange}
                placeholder="*.md, *.txt"
                placeholderTextColor={theme.colors.text + '60'}
              />
            </View>

            <View style={[styles.divider, { backgroundColor: theme.colors.border }]} />

            {/* Hide Files/Folders Matching */}
            <View style={styles.inputRow}>
              <Text style={[styles.inputLabel, { color: theme.colors.text }]}>
                Hide Files/Folders
              </Text>
              <TextInput
                style={[
                  styles.textInput,
                  {
                    color: theme.colors.text,
                    backgroundColor: theme.colors.background,
                    borderColor: theme.colors.border,
                  },
                ]}
                value={hiddenFileFolderFilter}
                onChangeText={handleHiddenFileFolderFilterChange}
                placeholder=".git, .noted"
                placeholderTextColor={theme.colors.text + '60'}
              />
            </View>

            <Text style={[styles.hintText, { color: theme.colors.text, opacity: 0.5 }]}>
              Filter which files appear in the sidebar. Use commas for multiple patterns or * for all files. Hide matching files/folders with patterns like .git, .noted
            </Text>
          </View>
        </View>

        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: theme.colors.text }]}>
            Daily Notes
          </Text>

          <View style={[styles.card, { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 3 }]}>
            {/* Enable Daily Notes Toggle */}
            <View style={styles.settingRow}>
              <Text style={[styles.settingLabel, { color: theme.colors.text }]}>
                Enable Daily Notes
              </Text>
              <TouchableOpacity
                style={[
                  styles.toggle,
                  { backgroundColor: dailyNotesEnabled ? theme.colors.primary : theme.colors.border }
                ]}
                onPress={() => handleDailyNotesToggle(!dailyNotesEnabled)}
                disabled={isLoadingSettings}
              >
                <Text style={[styles.toggleText, { color: theme.colors.background }]}>
                  {dailyNotesEnabled ? 'ON' : 'OFF'}
                </Text>
              </TouchableOpacity>
            </View>

            {dailyNotesEnabled && (
              <>
                <View style={[styles.divider, { backgroundColor: theme.colors.border }]} />

                {/* Open on Startup Toggle */}
                <View style={styles.settingRow}>
                  <Text style={[styles.settingLabel, { color: theme.colors.text }]}>
                    Open on Startup
                  </Text>
                  <TouchableOpacity
                    style={[
                      styles.toggle,
                      { backgroundColor: dailyNotesOpenOnStartup ? theme.colors.primary : theme.colors.border }
                    ]}
                    onPress={() => handleOpenOnStartupToggle(!dailyNotesOpenOnStartup)}
                    disabled={isLoadingSettings}
                  >
                    <Text style={[styles.toggleText, { color: theme.colors.background }]}>
                      {dailyNotesOpenOnStartup ? 'ON' : 'OFF'}
                    </Text>
                  </TouchableOpacity>
                </View>

                <View style={[styles.divider, { backgroundColor: theme.colors.border }]} />

                {/* Daily Notes Folder Input */}
                <View style={styles.inputRow}>
                  <Text style={[styles.inputLabel, { color: theme.colors.text }]}>
                    Folder Name
                  </Text>
                  <TextInput
                    style={[
                      styles.textInput,
                      {
                        color: theme.colors.text,
                        backgroundColor: theme.colors.background,
                        borderColor: theme.colors.border,
                      },
                    ]}
                    value={dailyNotesFolder}
                    onChangeText={handleFolderChange}
                    placeholder="daily"
                    placeholderTextColor={theme.colors.text + '60'}
                    editable={!isLoadingSettings}
                  />
                </View>

                <View style={[styles.divider, { backgroundColor: theme.colors.border }]} />

                {/* Template Selection */}
                <View style={styles.inputRow}>
                  <Text style={[styles.inputLabel, { color: theme.colors.text }]}>
                    Template
                  </Text>
                  <TouchableOpacity
                    style={[
                      styles.dropdownButton,
                      { backgroundColor: theme.colors.background, borderColor: theme.colors.border }
                    ]}
                    onPress={() => {
                      if (availableTemplates.length > 0) {
                        Alert.alert(
                          'Select Template',
                          'Choose a template for daily notes',
                          [
                            { text: 'None', onPress: () => handleTemplateChange('') },
                            ...availableTemplates.map(template => ({
                              text: template,
                              onPress: () => handleTemplateChange(template),
                            })),
                            { text: 'Cancel', style: 'cancel' as const },
                          ]
                        );
                      }
                    }}
                  >
                    <Text style={{ color: theme.colors.text, fontSize: 16 }}>
                      {dailyNotesTemplate || 'None'}
                    </Text>
                    <MaterialIcons name="arrow-drop-down" size={24} color={theme.colors.text} />
                  </TouchableOpacity>
                </View>

                <Text style={[styles.hintText, { color: theme.colors.text, opacity: 0.5 }]}>
                  {availableTemplates.length > 0 
                    ? "Select a template from your templates folder" 
                    : "Place templates in the templates folder to select one"}
                </Text>
              </>
            )}
          </View>
        </View>

        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: theme.colors.text }]}>
            Templates
          </Text>

          <View style={[styles.card, { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 3 }]}>
            <View style={styles.inputRow}>
              <Text style={[styles.inputLabel, { color: theme.colors.text }]}>
                Templates Folder
              </Text>
              <TextInput
                style={[
                  styles.textInput,
                  {
                    color: theme.colors.text,
                    backgroundColor: theme.colors.background,
                    borderColor: theme.colors.border,
                  },
                ]}
                value={templatesDirectory}
                onChangeText={handleTemplatesDirectoryChange}
                placeholder="templates"
                placeholderTextColor={theme.colors.text + '60'}
              />
            </View>

            <Text style={[styles.hintText, { color: theme.colors.text, opacity: 0.5 }]}>
              Place .md template files in this folder. Use {'{{year}}'}, {'{{month}}'}, {'{{day}}'}, {'{{hour}}'}, {'{{minute}}'}, {'{{ampm}}'}, {'{{cursor}}'} variables.
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
      </KeyboardAvoidingView>
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
  inputRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  inputLabel: {
    fontSize: 16,
    fontWeight: '600',
    flex: 1,
  },
  textInput: {
    flex: 1.5,
    fontSize: 16,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    borderWidth: 1,
    marginLeft: 12,
  },
  pickerContainer: {
    flex: 1.5,
    borderRadius: 8,
    borderWidth: 1,
    marginLeft: 12,
    overflow: 'hidden',
  },
  dropdownButton: {
    flex: 1.5,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderRadius: 8,
    borderWidth: 1,
    marginLeft: 12,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  hintText: {
    fontSize: 12,
    marginTop: 8,
    fontStyle: 'italic',
  },
});
