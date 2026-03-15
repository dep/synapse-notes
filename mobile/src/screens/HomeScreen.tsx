import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import { useTheme } from '../theme/ThemeContext';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';
import { FileDrawer } from '../components/FileDrawer';
import { FileSystemService } from '../services/FileSystemService';
import { OnboardingStorage } from '../services/onboardingStorage';
import { DailyNoteService } from '../services/DailyNoteService';
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
  const [repositoryPath, setRepositoryPath] = useState<string>(getVaultPath());
  const [hasOpenedDailyNote, setHasOpenedDailyNote] = useState(false);

  const repoName = repositoryPath
    ? repositoryPath.replace(/\/+$/, '').split('/').pop() || null
    : null;

  useEffect(() => {
    const loadRepositoryPath = async () => {
      const savedPath = await OnboardingStorage.getActiveRepositoryPath();
      if (savedPath) {
        setRepositoryPath(savedPath);
      }
    };

    loadRepositoryPath();
  }, []);

  // Open daily note on startup if enabled
  useEffect(() => {
    const openDailyNoteOnStartup = async () => {
      if (hasOpenedDailyNote || !repositoryPath) return;
      
      const shouldOpen = await DailyNoteService.getDailyNoteStatus();
      if (shouldOpen) {
        try {
          const result = await DailyNoteService.openTodayNote(repositoryPath);
          if (result.notePath) {
            setActiveFilePath(result.notePath);
            navigation.navigate('Editor', { filePath: result.notePath });
          }
        } catch (error) {
          console.error('Failed to open daily note on startup:', error);
        }
      }
      setHasOpenedDailyNote(true);
    };

    openDailyNoteOnStartup();
  }, [repositoryPath, hasOpenedDailyNote, navigation]);

  // Open drawer when coming back from editor with openDrawer param
  useEffect(() => {
    if (route.params?.openDrawer) {
      setIsDrawerOpen(true);
      // Clear the param so it doesn't reopen on subsequent renders
      navigation.setParams({ openDrawer: undefined });
    }
  }, [route.params?.openDrawer]);

  const handleFileSelect = (path: string) => {
    setActiveFilePath(path);
    navigation.navigate('Editor', { filePath: path });
  };

  const handleNewNote = async () => {
    try {
      // Generate a unique filename
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      const fileName = `Untitled-${timestamp}.md`;
      const filePath = `${repositoryPath}/${fileName}`;

      // Create the file with empty content
      await FileSystemService.writeFile(filePath, '# New Note\n\n');

      // Open the new file in the editor
      setActiveFilePath(filePath);
      navigation.navigate('Editor', { filePath });
    } catch (error) {
      console.error('Failed to create new note:', error);
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
      {/* Header with Hamburger Menu */}
      <View style={[styles.header, { backgroundColor: theme.colors.card, borderBottomColor: theme.colors.border }]}>
        <FileDrawer
          isOpen={isDrawerOpen}
          onClose={handleCloseDrawer}
          onFileSelect={handleFileSelect}
          onNewNote={handleNewNote}
          vaultPath={repositoryPath}
          repoName={repoName}
          activeFilePath={activeFilePath}
        />
        <Text style={[styles.headerTitle, { color: theme.colors.text }]}>
          Synapse
        </Text>
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
    paddingHorizontal: 12,
    paddingVertical: 16,
    borderBottomWidth: 1,
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 3,
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
});
