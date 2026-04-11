import React, { useEffect, useRef, useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView, Alert, Modal, TextInput, KeyboardAvoidingView, Platform, AppState, AppStateStatus, ActivityIndicator } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import { useTheme } from '../theme/ThemeContext';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';
import { FileDrawer } from '../components/FileDrawer';
import { TemplatePicker } from '../components/TemplatePicker';
import { FileSystemService } from '../services/FileSystemService';
import { OnboardingStorage } from '../services/onboardingStorage';
import { DailyNoteService } from '../services/DailyNoteService';
import { TemplateStorage } from '../services/TemplateStorage';
import { PinningStorage, PinnedItem } from '../services/PinningStorage';
import { GitService, GitErrorType, GitError } from '../services/gitService';
import { emitRepositoryRefresh } from '../services/repositoryEvents';
import * as FileSystem from 'expo-file-system/legacy';

type HomeScreenProps = NativeStackScreenProps<RootStackParamList, 'Home'>;

// Get the vault path from document directory
const getVaultPath = () => {
  const docDir = FileSystem.documentDirectory || 'file:///';
  // Android returns 'file:/data/user/...' which is malformed
  // We need 'file:///data/user/...' with three slashes after file:
  const fixedDir = docDir.replace(/^file:\/([^\/])/, 'file:///$1');
  // Ensure it ends with exactly one slash
  const normalizedDir = fixedDir.replace(/\/+$/, '') + '/';
  return `${normalizedDir}vault`;
};

export function HomeScreen({ navigation, route }: HomeScreenProps) {
  const { theme, isDark, toggleTheme, followSystem, setFollowSystem } = useTheme();
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);
  const [activeFilePath, setActiveFilePath] = useState<string | undefined>(undefined);
  const [repositoryPath, setRepositoryPath] = useState<string | null>(null);
  const [isTemplatePickerVisible, setIsTemplatePickerVisible] = useState(false);
  const [isNewFolderDialogVisible, setIsNewFolderDialogVisible] = useState(false);
  const [newFolderName, setNewFolderName] = useState('');
  const [pinnedItems, setPinnedItems] = useState<PinnedItem[]>([]);
  const [isSyncing, setIsSyncing] = useState(false);
  const appState = useRef<AppStateStatus>('active');

  const repoName = repositoryPath
    ? repositoryPath.replace(/\/+$/, '').split('/').pop() || null
    : null;

  useEffect(() => {
    const loadRepositoryPath = async () => {
      const savedPath = await OnboardingStorage.getActiveRepositoryPath();
      setRepositoryPath(savedPath ?? getVaultPath());
    };

    loadRepositoryPath();
  }, []);

  // Load pinned items when repository path changes
  useEffect(() => {
    const loadPinnedItems = async () => {
      if (!repositoryPath) return;
      try {
        const items = await PinningStorage.getPinnedItems(repositoryPath);
        setPinnedItems(items);
      } catch (error) {
        console.error('Failed to load pinned items:', error);
      }
    };

    loadPinnedItems();
  }, [repositoryPath]);

  // Open drawer when coming back from editor with openDrawer param
  useEffect(() => {
    if (route.params?.openDrawer) {
      setIsDrawerOpen(true);
      // Clear the param so it doesn't reopen on subsequent renders
      navigation.setParams({ openDrawer: undefined });
    }
  }, [route.params?.openDrawer]);

  // Pull latest from remote in the background
  const pullLatest = async (repoPath: string) => {
    if (!repoPath) return;
    setIsSyncing(true);
    try {
      await GitService.refreshRemote(repoPath);
      await emitRepositoryRefresh(repoPath);
    } catch (error) {
      console.error('[HomeScreen] Background pull failed:', error);
      if (error instanceof GitError && error.type === GitErrorType.AUTH_FAILURE) {
        Alert.alert(
          'GitHub Authentication Failed',
          'Your GitHub token is invalid or expired. Please update it in Settings.',
          [
            { text: 'Dismiss', style: 'cancel' },
            { text: 'Go to Settings', onPress: () => navigation.navigate('Settings') },
          ],
        );
      }
    } finally {
      setIsSyncing(false);
    }
  };

  // Pull on mount (once repository path is known)
  useEffect(() => {
    if (repositoryPath) {
      pullLatest(repositoryPath);
    }
  }, [repositoryPath]);

  // Pull again whenever the app comes back to the foreground
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (nextState: AppStateStatus) => {
      if (appState.current !== 'active' && nextState === 'active') {
        if (repositoryPath) {
          pullLatest(repositoryPath);
        }
      }
      appState.current = nextState;
    });

    return () => subscription.remove();
  }, [repositoryPath]);

  const handleFileSelect = (path: string) => {
    setActiveFilePath(path);
    navigation.navigate('Editor', { filePath: path });
  };

  const handleNewNote = () => {
    // Show template picker instead of creating directly
    setIsTemplatePickerVisible(true);
  };

  const handleTemplateSelect = async (templatePath: string | null, noteName: string) => {
    setIsTemplatePickerVisible(false);
    
    try {
      let filePath: string;
      
      if (templatePath) {
        // Create note from template
        const result = await TemplateStorage.createNoteFromTemplate(
          templatePath,
          repositoryPath,
          noteName
        );
        filePath = result.filePath;
      } else {
        // Create blank note
        filePath = await TemplateStorage.createBlankNote(repositoryPath, noteName);
      }
      
      setActiveFilePath(filePath);
      navigation.navigate('Editor', { filePath });
    } catch (error) {
      console.error('Failed to create note:', error);
    }
  };

  const handleNewFolder = () => {
    setIsNewFolderDialogVisible(true);
  };

  const handleCreateFolder = async (name: string) => {
    setIsNewFolderDialogVisible(false);
    if (!name.trim()) return;
    const safeName = name.trim().replace(/[\/\\:*?"<>|]/g, '_');
    const folderPath = `${repositoryPath}/${safeName}`;
    try {
      await FileSystemService.createDirectory(folderPath);
    } catch (error) {
      Alert.alert('Error', 'Failed to create folder');
      console.error('Failed to create folder:', error);
    }
  };

  const handleTodayNote = async () => {
    try {
      const result = await DailyNoteService.openTodayNote(repositoryPath);
      setActiveFilePath(result.notePath);
      navigation.navigate('Editor', { filePath: result.notePath });
    } catch (error) {
      console.error('Failed to open today\'s note:', error);
    }
  };

  const handleCloseDrawer = () => {
    setIsDrawerOpen(false);
  };

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.colors.background }]} edges={['top', 'left', 'right']}>
      <FileDrawer
        isOpen={isDrawerOpen}
        onClose={handleCloseDrawer}
        onFileSelect={handleFileSelect}
        onNewNote={handleNewNote}
        onNewFolder={handleNewFolder}
        onTodayNote={handleTodayNote}
        vaultPath={repositoryPath}
        repoName={repoName}
        activeFilePath={activeFilePath}
        showHamburger={false}
      />
      {/* Header with Hamburger Menu */}
      <View style={[styles.header, { backgroundColor: theme.colors.card, borderBottomColor: theme.colors.border }]}>
        <TouchableOpacity
          style={styles.hamburgerButton}
          onPress={() => setIsDrawerOpen(true)}
          testID="hamburger-button"
        >
          <MaterialIcons name="menu" size={28} color={theme.colors.text} />
        </TouchableOpacity>
        <Text style={[styles.headerTitle, { color: theme.colors.text }]}>
          Synapse
        </Text>
        {isSyncing && (
          <ActivityIndicator
            testID="sync-indicator"
            size="small"
            color={theme.colors.primary}
            style={styles.syncIndicator}
          />
        )}
        <TouchableOpacity
          style={styles.settingsButtonHeader}
          onPress={() => navigation.navigate('Settings')}
        >
          <MaterialIcons name="settings" size={24} color={theme.colors.text} />
        </TouchableOpacity>
      </View>

      <ScrollView
        style={styles.content}
        contentContainerStyle={styles.contentContainer}
      >
        <Text style={[styles.title, { color: theme.colors.text }]}>
          Welcome to Synapse
        </Text>

        <Text style={[styles.subtitle, { color: theme.colors.text }]}>
          Your mobile workspace for notes and ideas
        </Text>

        {/* Action Buttons */}
        <View style={[styles.section, { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 3 }]}>
          <TouchableOpacity
            style={[styles.button, { backgroundColor: theme.colors.secondary }]}
            onPress={handleNewNote}
          >
            <MaterialIcons name="note-add" size={20} color={theme.colors.background} style={{ marginRight: 8 }} />
            <Text style={[styles.buttonText, { color: theme.colors.background }]}>
              Create New Note
            </Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.button, { backgroundColor: theme.colors.primary, marginTop: 12 }]}
            onPress={handleTodayNote}
          >
            <MaterialIcons name="today" size={20} color={theme.colors.background} style={{ marginRight: 8 }} />
            <Text style={[styles.buttonText, { color: theme.colors.background }]}>
              Today's Note
            </Text>
          </TouchableOpacity>
        </View>

        {/* Pinned Items Section */}
        {pinnedItems.length > 0 && (
          <View style={[styles.pinnedSection, { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.05, shadowRadius: 8, elevation: 3 }]}>
            <View style={styles.pinnedHeader}>
              <MaterialIcons name="push-pin" size={18} color={theme.colors.primary} />
              <Text style={[styles.pinnedTitle, { color: theme.colors.text }]}>
                Pinned
              </Text>
            </View>
            <View style={styles.pinnedList}>
              {pinnedItems.map((item) => (
                <TouchableOpacity
                  key={item.id}
                  style={[styles.pinnedItem, { borderBottomColor: theme.colors.border }]}
                  onPress={() => handleFileSelect(item.path)}
                >
                  <MaterialIcons 
                    name={item.isFolder ? "folder" : "description"} 
                    size={18} 
                    color={theme.colors.primary} 
                  />
                  <Text style={[styles.pinnedItemText, { color: theme.colors.text }]} numberOfLines={1}>
                    {item.name.replace(/\.md$/, '')}
                  </Text>
                  <MaterialIcons name="chevron-right" size={20} color={theme.colors.text + '40'} />
                </TouchableOpacity>
              ))}
            </View>
          </View>
        )}
      </ScrollView>
      <TemplatePicker
        isVisible={isTemplatePickerVisible}
        onClose={() => setIsTemplatePickerVisible(false)}
        onSelectTemplate={handleTemplateSelect}
        vaultPath={repositoryPath}
      />

      {/* New Folder Dialog */}
      <Modal
        visible={isNewFolderDialogVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setIsNewFolderDialogVisible(false)}
      >
        <KeyboardAvoidingView
          style={styles.dialogOverlay}
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        >
          <View style={[styles.dialogBox, { backgroundColor: theme.colors.background, borderColor: theme.colors.border }]}>
            <Text style={[styles.dialogTitle, { color: theme.colors.text }]}>New Folder</Text>
            <TextInput
              style={[styles.dialogInput, { backgroundColor: theme.colors.card, color: theme.colors.text, borderColor: theme.colors.border }]}
              placeholder="Folder name"
              placeholderTextColor={theme.colors.text + '50'}
              value={newFolderName}
              onChangeText={setNewFolderName}
              autoFocus
              autoCapitalize="none"
              autoCorrect={false}
              returnKeyType="done"
              onSubmitEditing={() => {
                handleCreateFolder(newFolderName);
                setNewFolderName('');
              }}
            />
            <View style={styles.dialogButtons}>
              <TouchableOpacity
                style={styles.dialogCancelButton}
                onPress={() => {
                  setIsNewFolderDialogVisible(false);
                  setNewFolderName('');
                }}
              >
                <Text style={[styles.dialogCancelText, { color: theme.colors.text }]}>Cancel</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.dialogCreateButton, { backgroundColor: theme.colors.primary }]}
                onPress={() => {
                  handleCreateFolder(newFolderName);
                  setNewFolderName('');
                }}
              >
                <Text style={[styles.dialogCreateText, { color: theme.colors.background }]}>Create</Text>
              </TouchableOpacity>
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>
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
    paddingHorizontal: 12,
    paddingVertical: 16,
    borderBottomWidth: 1,
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 3,
  },
  hamburgerButton: {
    padding: 4,
    marginRight: 4,
  },
  headerTitle: {
    flex: 1,
    fontSize: 20,
    fontWeight: '700',
    textAlign: 'center',
    letterSpacing: -0.5,
  },
  headerSpacer: {
    width: 48,
  },
  content: {
    flex: 1,
  },
  contentContainer: {
    padding: 24,
  },
  title: {
    fontSize: 32,
    fontWeight: '800',
    marginBottom: 8,
    letterSpacing: -1,
  },
  subtitle: {
    fontSize: 16,
    marginBottom: 36,
    opacity: 0.8,
    fontWeight: '400',
  },
  section: {
    marginBottom: 32,
    padding: 20,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'transparent',
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 16,
    letterSpacing: -0.5,
  },
  settingRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
    paddingVertical: 4,
  },
  settingLabel: {
    fontSize: 16,
    fontWeight: '500',
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
    letterSpacing: 0.5,
  },
  button: {
    paddingHorizontal: 20,
    paddingVertical: 14,
    borderRadius: 12,
    alignItems: 'center',
    marginTop: 12,
    flexDirection: 'row',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  buttonText: {
    fontSize: 16,
    fontWeight: '700',
    letterSpacing: -0.2,
  },
  debugText: {
    fontSize: 12,
    fontFamily: 'monospace',
    marginBottom: 16,
    padding: 12,
    borderRadius: 8,
    backgroundColor: 'rgba(0,0,0,0.05)',
    overflow: 'hidden',
  },
  dialogOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
  },
  dialogBox: {
    width: '100%',
    borderRadius: 16,
    borderWidth: 1,
    padding: 24,
    gap: 16,
  },
  dialogTitle: {
    fontSize: 18,
    fontWeight: '700',
  },
  dialogInput: {
    height: 48,
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 14,
    fontSize: 16,
  },
  dialogButtons: {
    flexDirection: 'row',
    gap: 10,
    justifyContent: 'flex-end',
  },
  dialogCancelButton: {
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 10,
  },
  dialogCancelText: {
    fontSize: 16,
  },
  dialogCreateButton: {
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 10,
  },
  dialogCreateText: {
    fontSize: 16,
    fontWeight: '600',
  },
  pinnedSection: {
    width: '100%',
    borderRadius: 16,
    padding: 16,
    marginBottom: 16,
  },
  pinnedHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 12,
  },
  pinnedTitle: {
    fontSize: 16,
    fontWeight: '600',
  },
  pinnedList: {
    flexDirection: 'column',
  },
  pinnedItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderBottomWidth: 1,
    gap: 10,
  },
  pinnedItemText: {
    fontSize: 15,
    fontWeight: '500',
    flex: 1,
  },
});
