import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
  Alert,
  BackHandler,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import Markdown from 'react-native-markdown-display';
import { useTheme } from '../theme/ThemeContext';
import { FileSystemService, FileNode } from '../services/FileSystemService';
import { GitService } from '../services/gitService';
import { OnboardingStorage } from '../services/onboardingStorage';
import { subscribeToRepositoryRefresh } from '../services/repositoryEvents';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';
import { useFocusEffect } from '@react-navigation/native';

const getRelativePath = (root: string, filePath: string) => {
  const normalizedRoot = root.replace(/\/+$/, '');
  const normalizedFile = filePath.replace(/\/+$/, '');
  if (!normalizedFile.startsWith(normalizedRoot + '/')) {
    return normalizedFile;
  }
  return normalizedFile.slice(normalizedRoot.length + 1);
};

type EditorScreenProps = NativeStackScreenProps<RootStackParamList, 'Editor'>;

// WikiLink rule for markdown-it
const wikiLinkRule = (state: any, silent: boolean) => {
  const start = state.pos;
  const marker = state.src.charCodeAt(start);

  if (marker !== 0x5B /* [ */ || state.src.charCodeAt(start + 1) !== 0x5B /* [ */) {
    return false;
  }

  const end = state.src.indexOf(']]', start + 2);
  if (end === -1) return false;

  const content = state.src.slice(start + 2, end);
  if (!silent) {
    const token = state.push('wiki_link', 'wiki_link', 0);
    token.content = content;
    token.markup = '[[';
    token.info = ']]';
  }

  state.pos = end + 2;
  return true;
};

export function EditorScreen({ route, navigation }: EditorScreenProps) {
  const { filePath } = route.params;
  const { theme, isDark } = useTheme();
  const [content, setContent] = useState('');
  const [originalContent, setOriginalContent] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isPreviewMode, setIsPreviewMode] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [refreshStatus, setRefreshStatus] = useState<string | null>(null);
  
  // Wikilink picker state
  const [showWikilinkPicker, setShowWikilinkPicker] = useState(false);
  const [wikilinkSearch, setWikilinkSearch] = useState('');
  const [availableNotes, setAvailableNotes] = useState<FileNode[]>([]);
  const [filteredNotes, setFilteredNotes] = useState<FileNode[]>([]);
  const [wikilinkStartPos, setWikilinkStartPos] = useState<number | null>(null);
  const textInputRef = React.useRef<TextInput>(null);
  const editorScrollRef = React.useRef<ScrollView>(null);
  const shouldRestoreEditorFocusRef = React.useRef(false);
  const hasChangesRef = React.useRef(false);
  
  // Navigation history for back button support
  const [navigationHistory, setNavigationHistory] = useState<string[]>([]);
  
  // In-file search state
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchMatches, setSearchMatches] = useState<{ line: number; start: number; end: number; text: string }[]>([]);
  const [currentMatchIndex, setCurrentMatchIndex] = useState(0);

  useEffect(() => {
    loadFile();
  }, [filePath]);

  useEffect(() => {
    hasChangesRef.current = hasChanges;
  }, [hasChanges]);

  useEffect(() => {
    const unsubscribe = subscribeToRepositoryRefresh(async (repositoryPath) => {
      if (!filePath.startsWith(repositoryPath)) {
        return;
      }

      if (hasChanges) {
        setRefreshStatus('Remote updates available; save or discard local edits to reload');
        return;
      }

      try {
        const fileContent = await FileSystemService.readFile(filePath);
        setContent(fileContent);
        setOriginalContent(fileContent);
        setHasChanges(false);
        setRefreshStatus('Updated from remote');
        setTimeout(() => setRefreshStatus(null), 4000);
      } catch (err) {
        console.error('Failed to reload refreshed file:', err);
      }
    });

    return unsubscribe;
  }, [filePath, hasChanges]);

  const loadFile = async () => {
    setIsLoading(true);
    setError(null);
    try {
      const repositoryPath = await OnboardingStorage.getActiveRepositoryPath();
      if (repositoryPath) {
        try {
          await GitService.refreshRemote(repositoryPath);
        } catch (pullErr) {
          console.warn('Git refresh failed, using local version:', pullErr);
        }
      }
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

  // Check if file has been modified externally and prompt user
  const checkForExternalChanges = async () => {
    if (hasChanges) {
      // Don't check if user has unsaved changes - they're already editing
      return;
    }
    
    try {
      const fileContent = await FileSystemService.readFile(filePath);
      
      // If the content on disk is different from what we loaded originally
      if (fileContent !== originalContent && fileContent !== content) {
        Alert.alert(
          'Note Updated',
          'This note has been updated elsewhere. Would you like to load the latest version?',
          [
            {
              text: 'Keep Current',
              style: 'cancel',
              onPress: () => {
                // Update originalContent to match disk so we don't prompt again
                setOriginalContent(fileContent);
              },
            },
            {
              text: 'Get Latest',
              style: 'default',
              onPress: () => {
                setContent(fileContent);
                setOriginalContent(fileContent);
                setHasChanges(false);
              },
            },
          ]
        );
      }
    } catch (err) {
      console.error('Failed to check for external changes:', err);
    }
  };

  const handleContentChange = async (newContent: string) => {
    setContent(newContent);
    setHasChanges(newContent !== originalContent);
    
    // Detect "[[" pattern for wikilink picker
    if (!showWikilinkPicker) {
      const lastTwoChars = newContent.slice(-2);
      if (lastTwoChars === '[[') {
        // Show wikilink picker
        setShowWikilinkPicker(true);
        setWikilinkStartPos(newContent.length - 2);
        setWikilinkSearch('');
        
        // Load available notes
        try {
          const repositoryPath = await OnboardingStorage.getActiveRepositoryPath();
          if (repositoryPath) {
            const files = await FileSystemService.getFlatFileList(repositoryPath, {
              fileExtensionFilter: '*.md',
              hiddenFileFolderFilter: '.git',
            });
            setAvailableNotes(files);
            setFilteredNotes(files);
          }
        } catch (err) {
          console.error('Failed to load notes for wikilink picker:', err);
        }
      }
    } else {
      // Update search query based on what's typed after "[["
      if (wikilinkStartPos !== null) {
        const searchText = newContent.slice(wikilinkStartPos + 2);
        setWikilinkSearch(searchText);
        
        // Filter notes
        const filtered = availableNotes.filter(note => 
          note.name.toLowerCase().replace(/\.md$/, '').includes(searchText.toLowerCase())
        );
        setFilteredNotes(filtered);
      }
    }
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
      if (shouldRestoreEditorFocusRef.current && !isPreviewMode && !showWikilinkPicker) {
        setTimeout(() => {
          textInputRef.current?.focus();
          shouldRestoreEditorFocusRef.current = false;
        }, 0);
      }
    }
  };

  // Handle wikilink selection from picker
  const handleWikilinkSelect = (noteName: string) => {
    if (wikilinkStartPos !== null) {
      // Remove the "[[" and search text, insert the wikilink
      const beforeWikilink = content.slice(0, wikilinkStartPos);
      const afterWikilink = content.slice(wikilinkStartPos + 2 + wikilinkSearch.length);
      const newContent = `${beforeWikilink}[[${noteName.replace(/\.md$/, '')}]]${afterWikilink}`;
      
      setContent(newContent);
      setHasChanges(newContent !== originalContent);
      
      // Close picker
      setShowWikilinkPicker(false);
      setWikilinkStartPos(null);
      setWikilinkSearch('');
      setFilteredNotes([]);
    }
  };

  // Handle closing wikilink picker without selection
  const handleWikilinkDismiss = () => {
    setShowWikilinkPicker(false);
    setWikilinkStartPos(null);
    setWikilinkSearch('');
    setFilteredNotes([]);
  };

  // In-file search functions
  const openSearch = () => {
    setIsSearchOpen(true);
    setSearchQuery('');
    setSearchMatches([]);
    setCurrentMatchIndex(0);
  };

  const closeSearch = () => {
    setIsSearchOpen(false);
    setSearchQuery('');
    setSearchMatches([]);
    setCurrentMatchIndex(0);
  };

  const exitSearchAndEdit = (cursorPosition: number) => {
    // Close search mode
    setIsSearchOpen(false);
    setSearchQuery('');
    setSearchMatches([]);
    setCurrentMatchIndex(0);
    
    // Focus the text input and set cursor position
    setTimeout(() => {
      if (textInputRef.current) {
        textInputRef.current.focus();
        // Try to set selection if the API supports it
        try {
          // @ts-ignore - React Native TextInput may have setNativeProps
          textInputRef.current.setNativeProps({
            selection: { start: cursorPosition, end: cursorPosition }
          });
        } catch (e) {
          console.log('Could not set cursor position:', e);
        }
      }
    }, 100);
  };

  const performSearch = (query: string) => {
    setSearchQuery(query);
    if (!query.trim()) {
      setSearchMatches([]);
      setCurrentMatchIndex(0);
      return;
    }

    const lines = content.split('\n');
    const matches: { line: number; start: number; end: number; text: string }[] = [];
    const lowerQuery = query.toLowerCase();

    lines.forEach((line, lineIndex) => {
      let startIndex = 0;
      while (true) {
        const index = line.toLowerCase().indexOf(lowerQuery, startIndex);
        if (index === -1) break;
        matches.push({
          line: lineIndex,
          start: index,
          end: index + query.length,
          text: line,
        });
        startIndex = index + 1;
      }
    });

    setSearchMatches(matches);
    setCurrentMatchIndex(matches.length > 0 ? 0 : -1);
  };

  const goToNextMatch = () => {
    if (searchMatches.length === 0) return;
    const newIndex = (currentMatchIndex + 1) % searchMatches.length;
    setCurrentMatchIndex(newIndex);
    scrollToMatch(newIndex);
  };

  const goToPrevMatch = () => {
    if (searchMatches.length === 0) return;
    const newIndex = (currentMatchIndex - 1 + searchMatches.length) % searchMatches.length;
    setCurrentMatchIndex(newIndex);
    scrollToMatch(newIndex);
  };

  const scrollToMatch = (matchIndex: number) => {
    if (matchIndex < 0 || matchIndex >= searchMatches.length || !editorScrollRef.current) return;
    
    const match = searchMatches[matchIndex];
    const lineHeight = 26; // Approximate line height
    const scrollPosition = match.line * lineHeight;
    
    editorScrollRef.current.scrollTo({ y: scrollPosition, animated: true });
  };

  // Handle back navigation with unsaved changes
  const handleBackPress = useCallback(() => {
    if (hasChanges) {
      Alert.alert(
        'Save Changes?',
        'You have unsaved changes. Would you like to save them before leaving?',
        [
          {
            text: 'Cancel',
            style: 'cancel',
            onPress: () => {
              // Do nothing, stay on the screen
            },
          },
          {
            text: "Don't Save",
            style: 'destructive',
            onPress: () => {
              setHasChanges(false);
              navigation.navigate('Home', { openDrawer: true });
            },
          },
          {
            text: 'Save',
            style: 'default',
            onPress: async () => {
              await handleSave();
              navigation.navigate('Home', { openDrawer: true });
            },
          },
        ]
      );
      return true; // Prevent default back action
    }
    return false; // Allow default back action
  }, [hasChanges, navigation, content, originalContent]);

  // Intercept Android back button
  useFocusEffect(
    useCallback(() => {
      const onBackPress = () => {
        if (hasChanges) {
          handleBackPress();
          return true;
        }
        
        // Check if we have navigation history
        if (navigationHistory.length > 0) {
          // Get the last file from history
          const previousFile = navigationHistory[navigationHistory.length - 1];
          // Remove it from history
          setNavigationHistory(prev => prev.slice(0, -1));
          // Navigate back to the previous file
          navigation.navigate('Editor', { filePath: previousFile });
          return true;
        }
        
        // No history, go to home
        navigation.navigate('Home', { openDrawer: true });
        return true;
      };

      const subscription = BackHandler.addEventListener('hardwareBackPress', onBackPress);

      return () => subscription.remove();
    }, [hasChanges, handleBackPress, navigation, navigationHistory])
  );

  // Pull and reload every time the screen gains focus, unless the user has unsaved edits.
  useFocusEffect(
    useCallback(() => {
      if (!hasChangesRef.current) {
        loadFile();
      }
    }, [filePath])
  );

  // Intercept navigation before leaving
  useEffect(() => {
    const unsubscribe = navigation.addListener('beforeRemove', (e) => {
      if (!hasChanges) {
        return;
      }

      // Prevent default behavior
      e.preventDefault();

      // Show save dialog
      Alert.alert(
        'Save Changes?',
        'You have unsaved changes. Would you like to save them before leaving?',
        [
          {
            text: 'Cancel',
            style: 'cancel',
            onPress: () => {
              // Do nothing, stay on the screen
            },
          },
          {
            text: "Don't Save",
            style: 'destructive',
            onPress: () => {
              navigation.dispatch(e.data.action);
            },
          },
          {
            text: 'Save',
            style: 'default',
            onPress: async () => {
              try {
                await FileSystemService.writeFile(filePath, content);
                const repositoryPath = await OnboardingStorage.getActiveRepositoryPath();
                if (repositoryPath) {
                  await GitService.sync(repositoryPath, [getRelativePath(repositoryPath, filePath)]);
                }
                navigation.dispatch(e.data.action);
              } catch (err) {
                console.error('Failed to save file:', err);
                Alert.alert('Error', 'Failed to save file. Staying on screen.');
              }
            },
          },
        ]
      );
    });

    return unsubscribe;
  }, [navigation, hasChanges, content, filePath, originalContent]);

  const getFileName = () => {
    const parts = filePath.split('/');
    return parts[parts.length - 1] || 'Untitled';
  };

  const handleTogglePreview = () => {
    setIsPreviewMode(!isPreviewMode);
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    setRefreshStatus(null);
    try {
      const repositoryPath = await OnboardingStorage.getActiveRepositoryPath();
      setRefreshStatus(`repo: ${repositoryPath ?? 'none'}`);
      if (repositoryPath) {
        setRefreshStatus(`pulling from: ${repositoryPath}`);
        await GitService.refreshRemote(repositoryPath);
        setRefreshStatus('pull done — reading file…');
      }
      const fileContent = await FileSystemService.readFile(filePath);
      setContent(fileContent);
      setOriginalContent(fileContent);
      setHasChanges(false);
      setRefreshStatus(`✓ loaded (${fileContent.length} chars)`);
      setTimeout(() => setRefreshStatus(null), 4000);
    } catch (err: any) {
      setRefreshStatus(`✗ ${err?.message ?? String(err)}`);
    } finally {
      setIsRefreshing(false);
    }
  };

  // Parse wiki links for custom rendering
  const parseWikiLinks = (text: string): string => {
    // Convert [[Target|Display]] or [[Target]] to markdown links
    return text.replace(
      /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g,
      (match, target, display) => {
        const displayText = display || target;
        return `[${displayText}](synapse://wikilink/${encodeURIComponent(target)})`;
      }
    );
  };

  // Markdown styles based on theme
  const markdownStyles = {
    body: {
      color: theme.colors.text,
      fontSize: 16,
      lineHeight: 26,
    },
    heading1: {
      color: theme.colors.text,
      fontSize: 28,
      fontWeight: '700' as const,
      marginBottom: 16,
      marginTop: 24,
    },
    heading2: {
      color: theme.colors.text,
      fontSize: 22,
      fontWeight: '700' as const,
      marginBottom: 12,
      marginTop: 20,
    },
    heading3: {
      color: theme.colors.text,
      fontSize: 18,
      fontWeight: '600' as const,
      marginBottom: 10,
      marginTop: 16,
    },
    heading4: {
      color: theme.colors.text,
      fontSize: 16,
      fontWeight: '600' as const,
      marginBottom: 8,
      marginTop: 12,
    },
    heading5: {
      color: theme.colors.text,
      fontSize: 15,
      fontWeight: '600' as const,
    },
    heading6: {
      color: theme.colors.text,
      fontSize: 14,
      fontWeight: '600' as const,
    },
    strong: {
      fontWeight: '700' as const,
      color: theme.colors.text,
    },
    em: {
      fontStyle: 'italic' as const,
      color: theme.colors.text,
    },
    code_inline: {
      backgroundColor: isDark ? '#2d2d2d' : '#f0f0f0',
      color: isDark ? '#e0e0e0' : '#333',
      fontFamily: 'monospace',
      fontSize: 14,
      paddingHorizontal: 4,
      paddingVertical: 2,
      borderRadius: 4,
    },
    code_block: {
      backgroundColor: isDark ? '#1e1e1e' : '#f5f5f5',
      color: isDark ? '#d4d4d4' : '#333',
      fontFamily: 'monospace',
      fontSize: 14,
      padding: 16,
      borderRadius: 8,
      marginVertical: 12,
    },
    link: {
      color: theme.colors.primary,
      textDecorationLine: 'underline' as const,
    },
    blockquote: {
      backgroundColor: isDark ? '#2d2d2d' : '#f0f0f0',
      borderLeftWidth: 4,
      borderLeftColor: theme.colors.primary,
      paddingLeft: 16,
      paddingVertical: 8,
      marginVertical: 12,
      color: theme.colors.text,
    },
    bullet_list: {
      marginVertical: 8,
    },
    ordered_list: {
      marginVertical: 8,
    },
    list_item: {
      marginVertical: 4,
    },
    paragraph: {
      marginVertical: 8,
    },
  };

  // Custom render rules for wiki links
  const renderRules = {
    link: (node: any, children: any, parent: any, styles: any) => {
      const { href } = node.attributes;
      
      // Check if it's a wiki link
      if (href && href.startsWith('synapse://wikilink/')) {
        return (
          <Text
            key={node.key}
            style={{
              color: '#4A90E2', // Distinct blue color for wiki links
              textDecorationLine: 'underline',
              fontWeight: '500',
            }}
            onPress={() => handleLinkPress(href)}
          >
            {children}
          </Text>
        );
      }
      
      // Regular link
      return (
        <Text
          key={node.key}
          style={{
            color: theme.colors.primary,
            textDecorationLine: 'underline',
          }}
          onPress={() => handleLinkPress(href)}
        >
          {children}
        </Text>
      );
    },
  };

  // Handle wikilink taps in preview mode
  const handleLinkPress = async (url: string): Promise<boolean> => {
    // Check if it's a wikilink
    if (url.startsWith('synapse://wikilink/')) {
      try {
        // Extract the target from the URL
        const encodedTarget = url.replace('synapse://wikilink/', '');
        const target = decodeURIComponent(encodedTarget);

        // Get the repository path
        const repositoryPath = await OnboardingStorage.getActiveRepositoryPath();
        if (!repositoryPath) {
          Alert.alert('Error', 'No active repository found');
          return false;
        }

        // Resolve the wikilink to an actual file path
        const resolvedPath = await FileSystemService.resolveWikilink(target, repositoryPath);

        if (resolvedPath) {
          // Save current file before navigating if there are changes
          if (hasChanges) {
            try {
              await FileSystemService.writeFile(filePath, content);
              const repoPath = await OnboardingStorage.getActiveRepositoryPath();
              if (repoPath) {
                await GitService.sync(repoPath, [getRelativePath(repoPath, filePath)]);
              }
            } catch (err) {
              console.error('Failed to save before navigation:', err);
              Alert.alert('Error', 'Failed to save current note');
              return false;
            }
          }
          // Add current file to navigation history before navigating
          setNavigationHistory(prev => [...prev, filePath]);
          // Navigate to the resolved note
          navigation.navigate('Editor', { filePath: resolvedPath });
        } else {
          // Show "Note not found" alert with option to create
          Alert.alert(
            'Note not found',
            `The note "${target}" does not exist.`,
            [
              {
                text: 'Cancel',
                style: 'cancel',
              },
              {
                text: 'Create Note',
                onPress: async () => {
                  // Save current file before navigating if there are changes
                  if (hasChanges) {
                    try {
                      await FileSystemService.writeFile(filePath, content);
                      const repoPath = await OnboardingStorage.getActiveRepositoryPath();
                      if (repoPath) {
                        await GitService.sync(repoPath, [getRelativePath(repoPath, filePath)]);
                      }
                    } catch (err) {
                      console.error('Failed to save before navigation:', err);
                      Alert.alert('Error', 'Failed to save current note');
                      return;
                    }
                  }
                  // Create the note with the target name
                  const newFilePath = FileSystemService.join(repositoryPath, `${target}.md`);
                  try {
                    await FileSystemService.writeFile(newFilePath, `# ${target}\n\n`);
                    // Add current file to navigation history before navigating
                    setNavigationHistory(prev => [...prev, filePath]);
                    navigation.navigate('Editor', { filePath: newFilePath });
                  } catch (err) {
                    console.error('Failed to create note:', err);
                    Alert.alert('Error', 'Failed to create note');
                  }
                },
              },
            ]
          );
        }

        return false; // Prevent default link handling
      } catch (err) {
        console.error('Failed to handle wikilink:', err);
        Alert.alert('Error', 'Failed to navigate to note');
        return false;
      }
    }

    // For regular links, let the system handle them
    return true;
  };

  if (isLoading) {
    return (
      <View testID="editor-container" style={[styles.container, { backgroundColor: theme.colors.background }]}>
        <ActivityIndicator size="large" color={theme.colors.primary} />
      </View>
    );
  }

  const previewContent = parseWikiLinks(content);

  return (
    <SafeAreaView testID="editor-container" style={[styles.container, { backgroundColor: theme.colors.background }]} edges={['top', 'left', 'right']}>
      {/* Header */}
      <View style={[styles.header, { borderBottomColor: theme.colors.border }]}> 
        {/* Hamburger Menu Button */}
        <TouchableOpacity
          style={styles.menuButton}
          onPress={() => navigation.navigate('Home', { openDrawer: true })}
          testID="hamburger-menu-button"
        >
          <MaterialIcons name="menu" size={28} color={theme.colors.text} />
        </TouchableOpacity>
        
        <Text style={[styles.fileName, { color: theme.colors.text }]} numberOfLines={1}>
          {getFileName()}
        </Text>
        
        {hasChanges && (
          <MaterialIcons name="circle" size={12} color={theme.colors.primary} style={styles.unsavedIndicator} />
        )}

        {/* Refresh Button */}
        <TouchableOpacity
          style={styles.previewToggleButton}
          onPress={handleRefresh}
          disabled={isRefreshing}
          testID="refresh-button"
        >
          {isRefreshing
            ? <ActivityIndicator size="small" color={theme.colors.primary} />
            : <MaterialIcons name="refresh" size={24} color={theme.colors.primary} />
          }
        </TouchableOpacity>

        {/* Preview Toggle Button */}
        <TouchableOpacity
          style={styles.previewToggleButton}
          onPress={handleTogglePreview}
          testID="preview-toggle-button"
        >
          <MaterialIcons
            name={isPreviewMode ? "edit" : "visibility"}
            size={24}
            color={theme.colors.text}
          />
        </TouchableOpacity>
        
        {/* Search Button */}
        <TouchableOpacity
          style={styles.searchButton}
          onPress={openSearch}
          testID="search-button"
        >
          <MaterialIcons name="search" size={24} color={theme.colors.text} />
        </TouchableOpacity>
        
        <TouchableOpacity
          testID="save-button"
          style={[
            styles.saveButton,
            { backgroundColor: hasChanges ? theme.colors.primary : theme.colors.border },
          ]}
          onPressIn={() => {
            shouldRestoreEditorFocusRef.current = textInputRef.current?.isFocused() ?? false;
          }}
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

      {/* Search Overlay */}
      {isSearchOpen && (
        <View style={[styles.searchOverlay, { backgroundColor: theme.colors.card }]}>
          <View style={styles.searchHeader}>
            <TextInput
              testID="search-input"
              style={[styles.searchInput, { color: theme.colors.text, backgroundColor: isDark ? '#2d2d2d' : '#f0f0f0' }]}
              value={searchQuery}
              onChangeText={performSearch}
              placeholder="Search in note..."
              placeholderTextColor={theme.colors.text + '60'}
              autoFocus
            />
            {searchMatches.length > 0 && (
              <View style={styles.matchInfoContainer}>
                <Text style={[styles.matchCounter, { color: theme.colors.text }]}>
                  {currentMatchIndex + 1} of {searchMatches.length}
                </Text>
                {currentMatchIndex >= 0 && searchMatches[currentMatchIndex] && (
                  <Text style={[styles.matchLineInfo, { color: theme.colors.text + '80' }]}>
                    Line {searchMatches[currentMatchIndex].line + 1}
                  </Text>
                )}
              </View>
            )}
            <TouchableOpacity onPress={goToPrevMatch} disabled={searchMatches.length === 0} testID="search-prev-button">
              <MaterialIcons name="keyboard-arrow-up" size={24} color={searchMatches.length > 0 ? theme.colors.text : theme.colors.text + '40'} />
            </TouchableOpacity>
            <TouchableOpacity onPress={goToNextMatch} disabled={searchMatches.length === 0} testID="search-next-button">
              <MaterialIcons name="keyboard-arrow-down" size={24} color={searchMatches.length > 0 ? theme.colors.text : theme.colors.text + '40'} />
            </TouchableOpacity>
            <TouchableOpacity onPress={closeSearch} testID="search-close-button">
              <MaterialIcons name="close" size={24} color={theme.colors.text} />
            </TouchableOpacity>
          </View>
        </View>
      )}

      {/* Editor or Preview */}
      <KeyboardAvoidingView 
        style={styles.keyboardAvoidingView}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      >
        {isPreviewMode ? (
          // Preview Mode
          <ScrollView 
            testID="markdown-preview" 
            style={[styles.content, { backgroundColor: theme.colors.card }]}
            contentContainerStyle={styles.previewContent}
          >
            <Markdown 
              style={markdownStyles}
              rules={renderRules}
              onLinkPress={handleLinkPress}
            >
              {previewContent}
            </Markdown>
          </ScrollView>
        ) : (
          // Edit Mode
          <ScrollView 
            style={styles.content} 
            keyboardShouldPersistTaps="handled"
            ref={editorScrollRef}
          >
            {isSearchOpen && searchMatches.length > 0 ? (
              // Search Mode - Show highlighted text
              <View style={styles.searchableEditor}>
                {content.split('\n').map((line, lineIndex) => {
                  // Find matches on this line
                  const lineMatches = searchMatches.filter(m => m.line === lineIndex);
                  
                  // Calculate cursor position for this line
                  const lineStartPos = content.split('\n').slice(0, lineIndex).join('\n').length + (lineIndex > 0 ? 1 : 0);
                  
                  if (lineMatches.length === 0) {
                    return (
                      <TouchableOpacity 
                        key={lineIndex} 
                        onPress={() => exitSearchAndEdit(lineStartPos + line.length)}
                        activeOpacity={0.7}
                      >
                        <Text style={[styles.searchLine, { color: theme.colors.text }]}>
                          {line || ' '}
                        </Text>
                      </TouchableOpacity>
                    );
                  }
                  
                  // Build highlighted line
                  const parts: JSX.Element[] = [];
                  let lastEnd = 0;
                  
                  lineMatches.forEach((match, idx) => {
                    // Text before match
                    if (match.start > lastEnd) {
                      parts.push(
                        <Text key={`before-${idx}`} style={{ color: theme.colors.text }}>
                          {line.substring(lastEnd, match.start)}
                        </Text>
                      );
                    }
                    
                    // Highlighted match text
                    const isActiveMatch = lineIndex === searchMatches[currentMatchIndex]?.line && 
                                         match.start === searchMatches[currentMatchIndex]?.start;
                    parts.push(
                      <Text 
                        key={`match-${idx}`} 
                        style={{
                          backgroundColor: isActiveMatch ? theme.colors.primary : theme.colors.primary + '60',
                          color: theme.colors.background,
                          borderRadius: 2,
                          overflow: 'hidden',
                        }}
                      >
                        {line.substring(match.start, match.end)}
                      </Text>
                    );
                    
                    lastEnd = match.end;
                  });
                  
                  // Text after last match
                  if (lastEnd < line.length) {
                    parts.push(
                      <Text key="after" style={{ color: theme.colors.text }}>
                        {line.substring(lastEnd)}
                      </Text>
                    );
                  }
                  
                  return (
                    <TouchableOpacity 
                      key={lineIndex} 
                      onPress={() => exitSearchAndEdit(lineStartPos + line.length)}
                      activeOpacity={0.7}
                    >
                      <Text style={styles.searchLine}>
                        {parts.length > 0 ? parts : ' '}
                      </Text>
                    </TouchableOpacity>
                  );
                })}
              </View>
            ) : (
              // Normal Edit Mode
              <TextInput
                testID="editor-input"
                ref={textInputRef}
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
                undoEnabled={true}
              />
            )}
          </ScrollView>
        )}
      </KeyboardAvoidingView>

      {/* Wikilink Picker Modal */}
      {showWikilinkPicker && (
        <View style={styles.wikilinkModalOverlay}>
          <View style={[styles.wikilinkModal, { backgroundColor: theme.colors.card }]}>
            <View style={styles.wikilinkModalHeader}>
              <Text style={[styles.wikilinkModalTitle, { color: theme.colors.text }]}>
                Link to note
              </Text>
              <TouchableOpacity onPress={handleWikilinkDismiss}>
                <MaterialIcons name="close" size={24} color={theme.colors.text} />
              </TouchableOpacity>
            </View>
            
            <TextInput
              style={[styles.wikilinkSearchInput, { 
                color: theme.colors.text,
                backgroundColor: isDark ? '#2d2d2d' : '#f0f0f0',
                borderColor: theme.colors.border,
              }]}
              value={wikilinkSearch}
              onChangeText={(text) => {
                setWikilinkSearch(text);
                const filtered = availableNotes.filter(note => 
                  note.name.toLowerCase().replace(/\.md$/, '').includes(text.toLowerCase())
                );
                setFilteredNotes(filtered);
              }}
              placeholder="Search notes..."
              placeholderTextColor={theme.colors.text + '60'}
              autoFocus
            />
            
            <ScrollView style={styles.wikilinkList} keyboardShouldPersistTaps="handled">
              {filteredNotes.length === 0 ? (
                <Text style={[styles.wikilinkEmptyText, { color: theme.colors.text + '80' }]}>
                  {wikilinkSearch ? 'No notes found' : 'Type to search notes'}
                </Text>
              ) : (
                filteredNotes.map((note) => (
                  <TouchableOpacity
                    key={note.path}
                    style={styles.wikilinkListItem}
                    onPress={() => handleWikilinkSelect(note.name)}
                  >
                    <MaterialIcons name="description" size={20} color={theme.colors.primary} />
                    <Text style={[styles.wikilinkListItemText, { color: theme.colors.text }]}>
                      {note.name.replace(/\.md$/, '')}
                    </Text>
                  </TouchableOpacity>
                ))
              )}
            </ScrollView>
          </View>
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  keyboardAvoidingView: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 12,
    borderBottomWidth: 1,
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 3,
  },
  menuButton: {
    padding: 4,
    marginRight: 8,
    justifyContent: 'center',
    alignItems: 'center',
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
    fontSize: 16,
    fontWeight: '600',
    letterSpacing: -0.3,
  },
  unsavedIndicator: {
    marginRight: 8,
    fontSize: 14,
  },
  previewToggleButton: {
    padding: 8,
    marginRight: 8,
    justifyContent: 'center',
    alignItems: 'center',
  },
  saveButton: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 10,
    minWidth: 60,
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
  previewContent: {
    paddingHorizontal: 8,
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
  wikilinkModalOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 1000,
  },
  wikilinkModal: {
    width: '80%',
    maxHeight: '60%',
    borderRadius: 16,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 8,
  },
  wikilinkModalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  wikilinkModalTitle: {
    fontSize: 18,
    fontWeight: '600',
  },
  wikilinkSearchInput: {
    height: 44,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    fontSize: 16,
    marginBottom: 12,
  },
  wikilinkList: {
    maxHeight: 300,
  },
  wikilinkListItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 8,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(0, 0, 0, 0.1)',
  },
  wikilinkListItemText: {
    fontSize: 16,
    marginLeft: 12,
  },
  wikilinkEmptyText: {
    fontSize: 14,
    textAlign: 'center',
    paddingVertical: 24,
  },
  searchButton: {
    padding: 8,
    borderRadius: 8,
    marginHorizontal: 4,
  },
  searchOverlay: {
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(0, 0, 0, 0.1)',
  },
  searchHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  searchInput: {
    flex: 1,
    height: 40,
    borderRadius: 8,
    paddingHorizontal: 12,
    fontSize: 16,
  },
  matchCounter: {
    fontSize: 14,
    fontWeight: '500',
    minWidth: 50,
    textAlign: 'center',
  },
  matchInfoContainer: {
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
  },
  matchLineInfo: {
    fontSize: 11,
    marginTop: 2,
  },
  searchableEditor: {
    padding: 20,
    minHeight: '100%',
  },
  searchLine: {
    fontSize: 16,
    lineHeight: 26,
    fontFamily: 'monospace',
    flexWrap: 'wrap',
  },
});
