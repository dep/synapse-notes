import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import { useTheme } from '../theme/ThemeContext';
import { FileSystemService } from '../services/FileSystemService';
import { GitService } from '../services/gitService';
import { OnboardingStorage } from '../services/onboardingStorage';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';

const getRelativePath = (root: string, filePath: string) => {
  const normalizedRoot = root.replace(/\/+$/, '');
  const normalizedFile = filePath.replace(/\/+$/, '');
  if (!normalizedFile.startsWith(normalizedRoot + '/')) {
    return normalizedFile;
  }
  return normalizedFile.slice(normalizedRoot.length + 1);
};

type EditorScreenProps = NativeStackScreenProps<RootStackParamList, 'Editor'>;

export function EditorScreen({ route, navigation }: EditorScreenProps) {
  const { filePath } = route.params;
  const { theme } = useTheme();
  const [content, setContent] = useState('');
  const [originalContent, setOriginalContent] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadFile();
  }, [filePath]);

  const loadFile = async () => {
    setIsLoading(true);
    setError(null);
    try {
      const fileContent = await FileSystemService.readFile(filePath);
      setContent(fileContent);
      setOriginalContent(fileContent);
      setHasChanges(false);
    } catch (err) {
      console.error('Failed to load file:', err);
      setError('Failed to load file');
    } finally {
      setIsLoading(false);
    }
  };

  const handleContentChange = (newContent: string) => {
    setContent(newContent);
    setHasChanges(newContent !== originalContent);
  };

  const handleSave = async () => {
    if (!hasChanges) return;

    setIsSaving(true);
    setError(null);
    try {
      await FileSystemService.writeFile(filePath, content);
      const repositoryPath = await OnboardingStorage.getActiveRepositoryPath();
      if (repositoryPath) {
        await GitService.sync(repositoryPath, [getRelativePath(repositoryPath, filePath)]);
      }
      setOriginalContent(content);
      setHasChanges(false);
    } catch (err) {
      console.error('Failed to save file:', err);
      setError('Failed to save file or sync repository');
    } finally {
      setIsSaving(false);
    }
  };

  const getFileName = () => {
    const parts = filePath.split('/');
    return parts[parts.length - 1] || 'Untitled';
  };

  if (isLoading) {
    return (
      <View style={[styles.container, { backgroundColor: theme.colors.background }]}>
        <ActivityIndicator size="large" color={theme.colors.primary} />
      </View>
    );
  }

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.colors.background }]} edges={['top', 'left', 'right']}>
      {/* Header */}
      <View style={[styles.header, { borderBottomColor: theme.colors.border }]}>
        <TouchableOpacity
          style={styles.backButton}
          onPress={() => navigation.navigate('Home', { openDrawer: true })}
          testID="back-button"
        >
          <MaterialIcons name="arrow-back" size={28} color={theme.colors.primary} />
        </TouchableOpacity>
        
        <Text style={[styles.fileName, { color: theme.colors.text }]} numberOfLines={1}>
          {getFileName()}
        </Text>
        {hasChanges && (
          <MaterialIcons name="circle" size={12} color={theme.colors.primary} style={styles.unsavedIndicator} />
        )}
        <TouchableOpacity
          style={[
            styles.saveButton,
            { backgroundColor: hasChanges ? theme.colors.primary : theme.colors.border },
          ]}
          onPress={handleSave}
          disabled={!hasChanges || isSaving}
        >
          {isSaving ? (
            <ActivityIndicator size="small" color={theme.colors.background} />
          ) : (
            <View style={{ flexDirection: 'row', alignItems: 'center' }}>
              <MaterialIcons name="save" size={18} color={theme.colors.background} style={{ marginRight: 4 }} />
              <Text style={[styles.saveButtonText, { color: theme.colors.background }]}>
                Save
              </Text>
            </View>
          )}
        </TouchableOpacity>
      </View>

      {/* Error Message */}
      {error && (
        <View style={[styles.errorContainer, { backgroundColor: theme.colors.error + '20' }]}>
          <Text style={[styles.errorText, { color: theme.colors.error }]}>{error}</Text>
        </View>
      )}

      {/* Editor */}
      <ScrollView style={styles.content}>
        <TextInput
          style={[
            styles.editor,
            {
              color: theme.colors.text,
              backgroundColor: theme.colors.card,
            },
          ]}
          multiline
          value={content}
          onChangeText={handleContentChange}
          placeholder="Start typing..."
          placeholderTextColor={theme.colors.text + '60'}
          textAlignVertical="top"
          autoCapitalize="none"
          autoCorrect={false}
          spellCheck={false}
        />
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
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 3,
  },
  backButton: {
    paddingRight: 12,
    marginRight: 4,
    justifyContent: 'center',
    alignItems: 'center',
  },
  backButtonText: {
    fontSize: 26,
    fontWeight: '500',
    lineHeight: 28,
  },
  fileName: {
    flex: 1,
    fontSize: 18,
    fontWeight: '700',
    letterSpacing: -0.3,
  },
  unsavedIndicator: {
    marginRight: 12,
    fontSize: 14,
  },
  saveButton: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 12,
    minWidth: 70,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  saveButtonText: {
    fontSize: 14,
    fontWeight: '700',
    letterSpacing: -0.2,
  },
  errorContainer: {
    padding: 16,
    margin: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(239, 68, 68, 0.3)',
  },
  errorText: {
    fontSize: 14,
    textAlign: 'center',
    fontWeight: '500',
  },
  content: {
    flex: 1,
    padding: 16,
  },
  editor: {
    flex: 1,
    minHeight: '100%',
    padding: 20,
    borderRadius: 16,
    fontSize: 16,
    lineHeight: 26,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 8,
    elevation: 3,
  },
});
