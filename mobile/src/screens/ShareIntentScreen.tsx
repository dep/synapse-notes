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
import { useShareIntentContext } from 'expo-share-intent';
import { useTheme } from '../theme/ThemeContext';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';
import { FileSystemService } from '../services/FileSystemService';
import { GitService } from '../services/gitService';
import { OnboardingStorage } from '../services/onboardingStorage';
import { SettingsStorage } from '../services/SettingsStorage';

type ShareIntentScreenProps = NativeStackScreenProps<RootStackParamList, 'ShareIntent'>;

export function ShareIntentScreen({ navigation }: ShareIntentScreenProps) {
  const { theme } = useTheme();
  const { shareIntent, resetShareIntent } = useShareIntentContext();
  const [noteName, setNoteName] = useState('');
  const [saveFolder, setSaveFolder] = useState('');
  const [isSaving, setIsSaving] = useState(false);

  // Load persisted folder on mount
  React.useEffect(() => {
    SettingsStorage.getShareDefaultFolder().then(folder => {
      setSaveFolder(folder);
    });
  }, []);

  const getDefaultNoteName = () => {
    if (shareIntent?.meta?.title) {
      // Sanitize the title as a filename
      return shareIntent.meta.title.replace(/[^a-zA-Z0-9 \-_]/g, '').trim().slice(0, 60);
    }
    if (shareIntent?.webUrl) {
      try {
        const url = new URL(shareIntent.webUrl);
        return url.hostname.replace(/^www\./, '');
      } catch {
        // ignore parse error
      }
    }
    return '';
  };

  const getContentPreview = () => {
    if (shareIntent?.type === 'weburl' || shareIntent?.type === 'text') {
      return shareIntent.text || '';
    }
    return '';
  };

  const buildNoteContent = () => {
    const lines: string[] = [];
    const name = (noteName.trim() || getDefaultNoteName() || 'Shared Note');
    
    // Add YAML frontmatter with today's date
    const today = new Date();
    const dateStr = today.toISOString().split('T')[0]; // YYYY-MM-DD format
    lines.push('---');
    lines.push(`date: [[${dateStr}]]`);
    lines.push('---');
    lines.push('');

    lines.push(`# ${name}`);
    lines.push('');

    if (shareIntent?.meta?.title && shareIntent.meta.title !== name) {
      lines.push(`**${shareIntent.meta.title}**`);
      lines.push('');
    }

    if (shareIntent?.webUrl) {
      lines.push(shareIntent.webUrl);
      lines.push('');
    }

    if (shareIntent?.meta?.description) {
      lines.push(shareIntent.meta.description);
      lines.push('');
    }

    if (shareIntent?.text && shareIntent.text !== shareIntent?.webUrl) {
      lines.push(shareIntent.text);
    }

    return lines.join('\n').trimEnd();
  };

  const handleFolderChange = async (folder: string) => {
    setSaveFolder(folder);
    await SettingsStorage.setShareDefaultFolder(folder);
  };

  const handleSave = async () => {
    setIsSaving(true);
    try {
      const repositoryPath = await OnboardingStorage.getActiveRepositoryPath();
      if (!repositoryPath) {
        Alert.alert('No vault', 'Please set up a repository first.');
        return;
      }

      // Resolve target directory — relative paths are joined to the vault root
      const folderSegment = saveFolder.trim().replace(/^\/+|\/+$/g, '');
      const targetDir = folderSegment ? `${repositoryPath}/${folderSegment}` : repositoryPath;

      // Ensure the folder exists
      const folderExists = await FileSystemService.exists(targetDir);
      if (!folderExists) {
        await FileSystemService.createDirectory(targetDir, { recursive: true });
      }

      const fileName = (noteName.trim() || getDefaultNoteName() || 'Shared Note')
        .replace(/[^a-zA-Z0-9 \-_]/g, '')
        .trim()
        .slice(0, 80);
      const safeName = fileName.endsWith('.md') ? fileName : `${fileName}.md`;
      const relativePath = folderSegment ? `${folderSegment}/${safeName}` : safeName;
      const filePath = `${targetDir}/${safeName}`;
      const content = buildNoteContent();

      await FileSystemService.writeFile(filePath, content);

      try {
        await GitService.sync(repositoryPath, [relativePath]);
      } catch (syncError) {
        console.warn('[ShareIntent] Git sync failed (file saved locally):', syncError);
      }

      resetShareIntent();
      navigation.replace('Editor', { filePath });
    } catch (error) {
      console.error('[ShareIntent] Failed to save:', error);
      Alert.alert('Error', 'Failed to save note. Please try again.');
    } finally {
      setIsSaving(false);
    }
  };

  const handleDiscard = () => {
    resetShareIntent();
    navigation.goBack();
  };

  const contentPreview = getContentPreview();
  const defaultName = getDefaultNoteName();

  return (
    <SafeAreaView
      style={[styles.container, { backgroundColor: theme.colors.background }]}
      edges={['top', 'left', 'right', 'bottom']}
    >
      {/* Header */}
      <View style={[styles.header, { borderBottomColor: theme.colors.border }]}>
        <TouchableOpacity onPress={handleDiscard} style={styles.cancelButton}>
          <Text style={[styles.cancelText, { color: theme.colors.primary }]}>Discard</Text>
        </TouchableOpacity>
        <Text style={[styles.headerTitle, { color: theme.colors.text }]}>
          Save to Synapse
        </Text>
        <TouchableOpacity
          onPress={handleSave}
          disabled={isSaving}
          style={styles.saveButton}
        >
          {isSaving ? (
            <ActivityIndicator size="small" color={theme.colors.primary} />
          ) : (
            <Text style={[styles.saveText, { color: theme.colors.primary }]}>Save</Text>
          )}
        </TouchableOpacity>
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        keyboardShouldPersistTaps="handled"
        automaticallyAdjustKeyboardInsets={true}
      >
        {/* Note name */}
        <View style={styles.section}>
          <Text style={[styles.label, { color: theme.colors.text + '80' }]}>Note Name</Text>
          <TextInput
            style={[
              styles.nameInput,
              {
                backgroundColor: theme.colors.card,
                color: theme.colors.text,
                borderColor: theme.colors.border,
              },
            ]}
            value={noteName}
            onChangeText={setNoteName}
            placeholder={defaultName || 'Untitled'}
            placeholderTextColor={theme.colors.text + '40'}
            autoFocus={true}
            returnKeyType="done"
          />
        </View>

        {/* Save location */}
        <View style={styles.section}>
          <Text style={[styles.label, { color: theme.colors.text + '80' }]}>Save to Folder</Text>
          <View style={[styles.folderInputRow, { backgroundColor: theme.colors.card, borderColor: theme.colors.border }]}>
            <MaterialIcons name="folder" size={18} color="#f59e0b" style={styles.folderIcon} />
            <TextInput
              style={[styles.folderInput, { color: theme.colors.text }]}
              value={saveFolder}
              onChangeText={handleFolderChange}
              placeholder="Vault root"
              placeholderTextColor={theme.colors.text + '40'}
              autoCapitalize="none"
              autoCorrect={false}
              returnKeyType="done"
            />
            {saveFolder.length > 0 && (
              <TouchableOpacity onPress={() => handleFolderChange('')} hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}>
                <MaterialIcons name="close" size={16} color={theme.colors.text + '50'} />
              </TouchableOpacity>
            )}
          </View>
          <Text style={[styles.folderHint, { color: theme.colors.text + '50' }]}>
            Relative to vault root, e.g. inbox or notes/clippings
          </Text>
        </View>

        {/* Shared content preview */}
        {contentPreview ? (
          <View style={styles.section}>
            <Text style={[styles.label, { color: theme.colors.text + '80' }]}>Shared Content</Text>
            <View style={[styles.previewCard, { backgroundColor: theme.colors.card, borderColor: theme.colors.border }]}>
              {shareIntent?.meta?.title && (
                <Text style={[styles.previewTitle, { color: theme.colors.text }]} numberOfLines={2}>
                  {shareIntent.meta.title}
                </Text>
              )}
              {shareIntent?.webUrl && (
                <View style={styles.previewUrlRow}>
                  <MaterialIcons name="link" size={14} color={theme.colors.primary} />
                  <Text
                    style={[styles.previewUrl, { color: theme.colors.primary }]}
                    numberOfLines={1}
                  >
                    {shareIntent.webUrl}
                  </Text>
                </View>
              )}
              {shareIntent?.meta?.description && (
                <Text style={[styles.previewDescription, { color: theme.colors.text + '80' }]} numberOfLines={3}>
                  {shareIntent.meta.description}
                </Text>
              )}
              {!shareIntent?.webUrl && !shareIntent?.meta?.title && (
                <Text style={[styles.previewText, { color: theme.colors.text }]} numberOfLines={8}>
                  {contentPreview}
                </Text>
              )}
            </View>
          </View>
        ) : null}

        {/* What will be saved */}
        <View style={styles.section}>
          <Text style={[styles.label, { color: theme.colors.text + '80' }]}>Note Preview</Text>
          <View style={[styles.notePreview, { backgroundColor: theme.colors.card, borderColor: theme.colors.border }]}>
            <Text style={[styles.notePreviewText, { color: theme.colors.text + '70' }]}>
              {buildNoteContent()}
            </Text>
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
    paddingVertical: 14,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  cancelButton: {
    minWidth: 70,
    paddingVertical: 4,
  },
  cancelText: {
    fontSize: 16,
  },
  headerTitle: {
    flex: 1,
    fontSize: 17,
    fontWeight: '600',
    textAlign: 'center',
  },
  saveButton: {
    minWidth: 70,
    alignItems: 'flex-end',
    paddingVertical: 4,
  },
  saveText: {
    fontSize: 16,
    fontWeight: '600',
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: 20,
    paddingBottom: 40,
  },
  section: {
    marginBottom: 24,
  },
  label: {
    fontSize: 12,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
    marginBottom: 10,
  },
  nameInput: {
    height: 52,
    borderRadius: 12,
    paddingHorizontal: 16,
    fontSize: 17,
    borderWidth: 1,
  },
  folderInputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 12,
    borderWidth: 1,
    paddingHorizontal: 14,
    height: 52,
    gap: 8,
  },
  folderIcon: {
    flexShrink: 0,
  },
  folderInput: {
    flex: 1,
    fontSize: 16,
    height: '100%',
  },
  folderHint: {
    fontSize: 12,
    marginTop: 6,
    marginLeft: 2,
  },
  previewCard: {
    borderRadius: 12,
    padding: 16,
    borderWidth: 1,
    gap: 8,
  },
  previewTitle: {
    fontSize: 15,
    fontWeight: '600',
    lineHeight: 20,
  },
  previewUrlRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  previewUrl: {
    fontSize: 13,
    flex: 1,
  },
  previewDescription: {
    fontSize: 13,
    lineHeight: 18,
  },
  previewText: {
    fontSize: 14,
    lineHeight: 20,
  },
  notePreview: {
    borderRadius: 12,
    padding: 16,
    borderWidth: 1,
  },
  notePreviewText: {
    fontFamily: 'monospace',
    fontSize: 12,
    lineHeight: 18,
  },
});
