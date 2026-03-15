import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView } from 'react-native';
import { useTheme } from '../theme/ThemeContext';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';
import { FileDrawer } from '../components/FileDrawer';
import { FileSystemService } from '../services/FileSystemService';
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

export function HomeScreen({ navigation }: HomeScreenProps) {
  const { theme, isDark, toggleTheme, followSystem, setFollowSystem } = useTheme();
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);
  const [activeFilePath, setActiveFilePath] = useState<string | undefined>(undefined);

  const handleFileSelect = (path: string) => {
    setActiveFilePath(path);
    navigation.navigate('Editor', { filePath: path });
  };

  const handleNewNote = async () => {
    try {
      // Generate a unique filename
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      const fileName = `Untitled-${timestamp}.md`;
      const vaultPath = getVaultPath();
      const filePath = `${vaultPath}/${fileName}`;

      // Create the file with empty content
      await FileSystemService.writeFile(filePath, '# New Note\n\n');

      // Open the new file in the editor
      setActiveFilePath(filePath);
      navigation.navigate('Editor', { filePath });
    } catch (error) {
      console.error('Failed to create new note:', error);
    }
  };

  const handleCloseDrawer = () => {
    setIsDrawerOpen(false);
  };

  return (
    <View style={[styles.container, { backgroundColor: theme.colors.background }]}>
      {/* Header with Hamburger Menu */}
      <View style={[styles.header, { backgroundColor: theme.colors.card, borderBottomColor: theme.colors.border }]}>
        <FileDrawer
          isOpen={isDrawerOpen}
          onClose={handleCloseDrawer}
          onFileSelect={handleFileSelect}
          onNewNote={handleNewNote}
          vaultPath={getVaultPath()}
          activeFilePath={activeFilePath}
        />
        <Text style={[styles.headerTitle, { color: theme.colors.text }]}>
          Synapse
        </Text>
        <View style={styles.headerSpacer} />
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

        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: theme.colors.text }]}>
            Quick Actions
          </Text>

          <TouchableOpacity
            style={[styles.button, { backgroundColor: theme.colors.primary }]}
            onPress={() => setIsDrawerOpen(true)}
          >
            <Text style={[styles.buttonText, { color: theme.colors.background }]}>
              Open File Drawer
            </Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.button, { backgroundColor: theme.colors.secondary }]}
            onPress={handleNewNote}
          >
            <Text style={[styles.buttonText, { color: theme.colors.background }]}>
              Create New Note
            </Text>
          </TouchableOpacity>
        </View>

        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: theme.colors.text }]}>
            Theme Settings
          </Text>

          <View style={styles.settingRow}>
            <Text style={[styles.settingLabel, { color: theme.colors.text }]}>
              Follow System Preference
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

          <View style={styles.settingRow}>
            <Text style={[styles.settingLabel, { color: theme.colors.text }]}>
              Current Theme
            </Text>
            <Text style={[styles.settingValue, { color: theme.colors.primary }]}>
              {isDark ? 'Dark' : 'Light'}
            </Text>
          </View>

          <TouchableOpacity
            style={[styles.button, { backgroundColor: theme.colors.primary }]}
            onPress={toggleTheme}
            disabled={followSystem}
          >
            <Text style={[styles.buttonText, { color: theme.colors.background }]}>
              Toggle Theme
            </Text>
          </TouchableOpacity>
        </View>

        <View style={styles.section}>
          <Text style={[styles.sectionTitle, { color: theme.colors.text }]}>
            Navigation
          </Text>

          <TouchableOpacity
            style={[styles.button, { backgroundColor: theme.colors.secondary }]}
            onPress={() => navigation.navigate('Settings')}
          >
            <Text style={[styles.buttonText, { color: theme.colors.background }]}>
              Go to Settings
            </Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  headerTitle: {
    flex: 1,
    fontSize: 20,
    fontWeight: 'bold',
    textAlign: 'center',
  },
  headerSpacer: {
    width: 48, // Same width as hamburger button area
  },
  content: {
    flex: 1,
  },
  contentContainer: {
    padding: 20,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 16,
    marginBottom: 32,
    opacity: 0.7,
  },
  section: {
    marginBottom: 32,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: '600',
    marginBottom: 16,
  },
  settingRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  settingLabel: {
    fontSize: 16,
  },
  settingValue: {
    fontSize: 16,
    fontWeight: '600',
  },
  toggle: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
    minWidth: 50,
    alignItems: 'center',
  },
  toggleText: {
    fontSize: 12,
    fontWeight: '600',
  },
  button: {
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 8,
  },
  buttonText: {
    fontSize: 16,
    fontWeight: '600',
  },
});
