import React, { useState, useEffect, useCallback, useMemo } from 'react';
import {
  View,
  Text,
  Image,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
  Alert,
  BackHandler,
  KeyboardAvoidingView,
  Platform,
  Dimensions,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import Markdown from 'react-native-markdown-display';
import { useTheme, type ThemeColors } from '../theme/ThemeContext';
import { FileSystemService, FileNode } from '../services/FileSystemService';
import { GitService } from '../services/gitService';
import { OnboardingStorage } from '../services/onboardingStorage';
import { subscribeToRepositoryRefresh } from '../services/repositoryEvents';
import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { RootStackParamList } from '../navigation/AppNavigator';
import { useFocusEffect } from '@react-navigation/native';

const getRelativePath = (root: string, filePath: string) => {
  const normalizedRoot = FileSystemService.normalizeUri(root).replace(/\/+$/, '');
  const normalizedFile = FileSystemService.normalizeUri(filePath).replace(/\/+$/, '');
  if (!normalizedFile.startsWith(normalizedRoot + '/')) {
    return normalizedFile;
  }
  return normalizedFile.slice(normalizedRoot.length + 1);
};

export const hasUriScheme = (value: string) => /^[a-z][a-z0-9+.-]*:/i.test(value);

// markdown-it's validateLink blocks file:// URIs. We wrap them in a
// placeholder scheme that markdown-it accepts, then unwrap in the
// custom image render rule before passing to the native Image component.
export const LOCAL_IMAGE_SCHEME = 'synapse-local://';

export const resolveLocalMarkdownPath = (basePath: string, targetPath: string) => {
  if (!targetPath.trim() || hasUriScheme(targetPath.trim())) {
    return targetPath.trim();
  }

  const baseDir = FileSystemService.dirname(basePath);
  return FileSystemService.join(baseDir, targetPath.trim());
};

export const parseWikiLinks = (text: string): string => {
  return text.replace(
    /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g,
    (match, target, display) => {
      const displayText = display || target;
      return `[${displayText}](synapse://wikilink/${encodeURIComponent(target)})`;
    }
  );
};

export const parseImageEmbeds = (text: string, sourcePath: string): string => {
  const wrapLocal = (path: string) => {
    // Already a remote URI — leave it alone
    if (/^https?:\/\//i.test(path) || /^data:/i.test(path)) {
      return path;
    }
    // Wrap local / file:// paths so markdown-it won't strip them
    return `${LOCAL_IMAGE_SCHEME}${path}`;
  };

  const withWikiImageEmbeds = text.replace(
    /!\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g,
    (match, target, display) => {
      const resolvedPath = resolveLocalMarkdownPath(sourcePath, target);
      const altText = display || target;
      return `![${altText}](${wrapLocal(resolvedPath)})`;
    }
  );

  return withWikiImageEmbeds.replace(
    /!\[([^\]]*)\]\(((?![a-z][a-z0-9+.-]*:)[^)]+)\)/gi,
    (match, altText, src) => {
      const resolvedPath = resolveLocalMarkdownPath(sourcePath, src);
      return `![${altText}](${wrapLocal(resolvedPath)})`;
    }
  );
};

export const preparePreviewContent = (text: string, sourcePath: string): string => {
  return parseWikiLinks(parseImageEmbeds(text, sourcePath));
};

type EditorScreenProps = NativeStackScreenProps<RootStackParamList, 'Editor'>;

/** Compact markdown styles for the version-history preview (single readable size scale). */
function historyPreviewMarkdownStyles(colors: ThemeColors, isDark: boolean) {
  const text = colors.text;
  const base = 12; // Small persistent font size for history preview
  const lh = 18;
  const codeBg = isDark ? '#2d2d2d' : '#f0f0f0';
  const blockBg = isDark ? '#1e1e1e' : '#f5f5f5';
  const codeText = isDark ? '#e0e0e0' : '#333';
  return {
    body: { color: text, fontSize: base, lineHeight: lh },
    paragraph: { marginTop: 4, marginBottom: 4, fontSize: base, lineHeight: lh, color: text },
    text: { fontSize: base, lineHeight: lh, color: text },
    textgroup: { fontSize: base, lineHeight: lh },
    heading1: {
      color: text,
      fontSize: 16,
      lineHeight: 22,
      fontWeight: '700' as const,
      marginTop: 10,
      marginBottom: 5,
    },
    heading2: {
      color: text,
      fontSize: 14,
      lineHeight: 20,
      fontWeight: '700' as const,
      marginTop: 8,
      marginBottom: 4,
    },
    heading3: {
      color: text,
      fontSize: 13,
      lineHeight: 18,
      fontWeight: '600' as const,
      marginTop: 6,
      marginBottom: 3,
    },
    heading4: { color: text, fontSize: base, lineHeight: lh, fontWeight: '600' as const, marginTop: 5 },
    heading5: { color: text, fontSize: base, lineHeight: lh, fontWeight: '600' as const },
    heading6: { color: text, fontSize: base, lineHeight: lh, fontWeight: '600' as const },
    strong: { fontWeight: '700' as const, color: text, fontSize: base },
    em: { fontStyle: 'italic' as const, color: text, fontSize: base },
    s: { color: text, fontSize: base },
    blockquote: {
      backgroundColor: codeBg,
      borderLeftWidth: 3,
      borderLeftColor: colors.primary,
      paddingLeft: 10,
      paddingVertical: 6,
      marginVertical: 6,
    },
    code_inline: {
      backgroundColor: codeBg,
      color: codeText,
      fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
      fontSize: 12,
      paddingHorizontal: 4,
      borderRadius: 4,
    },
    code_block: {
      backgroundColor: blockBg,
      color: codeText,
      fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
      fontSize: 12,
      lineHeight: 18,
      padding: 10,
      borderRadius: 8,
      marginVertical: 6,
    },
    fence: {
      backgroundColor: blockBg,
      color: codeText,
      fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
      fontSize: 12,
      lineHeight: 18,
      padding: 10,
      borderRadius: 8,
      marginVertical: 6,
    },
    link: { color: colors.primary, fontSize: base, textDecorationLine: 'underline' as const },
    bullet_list: { marginVertical: 4 },
    ordered_list: { marginVertical: 4 },
    list_item: { fontSize: base, lineHeight: lh, color: text, marginVertical: 2 },
    image: { marginVertical: 6 },
    hr: { backgroundColor: colors.border, height: StyleSheet.hairlineWidth, marginVertical: 10 },
    table: { borderWidth: StyleSheet.hairlineWidth, borderColor: colors.border, marginVertical: 8 },
    tr: { borderBottomWidth: StyleSheet.hairlineWidth, borderColor: colors.border },
    th: { padding: 6, fontSize: 12, fontWeight: '600' as const, color: text },
    td: { padding: 6, fontSize: 12, color: text },
  };
}

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
  const insets = useSafeAreaInsets();
  const historyMdStyles = useMemo(
    () => historyPreviewMarkdownStyles(theme.colors, isDark),
    [theme.colors, isDark]
  );
  const [content, setContent] = useState('');
  const [originalContent, setOriginalContent] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isPreviewMode, setIsPreviewMode] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [refreshStatus, setRefreshStatus] = useState<string | null>(null);
  
  // File history state
  const [fileHistory, setFileHistory] = useState<Array<{ sha: string; message: string; date: Date }>>([]);
  const [showHistoryModal, setShowHistoryModal] = useState(false);
  const [selectedCommit, setSelectedCommit] = useState<{ sha: string; message: string; date: Date } | null>(null);
  const [historicalContent, setHistoricalContent] = useState<string | null>(null);
  const [isLoadingHistory, setIsLoadingHistory] = useState(false);
  
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

  const loadFileHistory = useCallback(async () => {
    try {
      const repositoryPath = await OnboardingStorage.getActiveRepositoryPath();
      if (!repositoryPath) {
        setFileHistory([]);
        return;
      }

      const isRepo = await GitService.isRepository(repositoryPath);
      if (!isRepo) {
        setFileHistory([]);
        return;
      }

      const relativePath = getRelativePath(repositoryPath, filePath);
      const history = await GitService.getFileHistory(repositoryPath, relativePath);
      setFileHistory(history);
    } catch (err) {
      console.error('Failed to load file history:', err);
      setFileHistory([]);
    }
  }, [filePath]);

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

  useEffect(() => {
    void loadFile();
    void loadFileHistory();
  }, [filePath, loadFileHistory]);

  useFocusEffect(
    useCallback(() => {
      void loadFileHistory();
    }, [loadFileHistory])
  );

  useEffect(() => {
    hasChangesRef.current = hasChanges;
  }, [hasChanges]);

  useEffect(() => {
    const unsubscribe = subscribeToRepositoryRefresh(async (repositoryPath) => {
      if (!filePath.startsWith(repositoryPath)) {
        return;
      }

      // Use the ref instead of the state variable so this callback always sees
      // the latest value, even mid-async-await when the closure would otherwise
      // be stale.
      if (hasChangesRef.current) {
        setRefreshStatus('Remote updates available; save or discard local edits to reload');
        return;
      }

      try {
        const fileContent = await FileSystemService.readFile(filePath);
        // Re-check after the async read in case the user started editing while
        // the file was being fetched.
        if (hasChangesRef.current) {
          setRefreshStatus('Remote updates available; save or discard local edits to reload');
          return;
        }
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
  }, [filePath]);

  const handleViewHistory = () => {
    void loadFileHistory();
    setShowHistoryModal(true);
    setSelectedCommit(null);
    setHistoricalContent(null);
  };

  const handleSelectCommit = async (commit: { sha: string; message: string; date: Date }) => {
    setSelectedCommit(commit);
    setIsLoadingHistory(true);
    try {
      const repositoryPath = await OnboardingStorage.getActiveRepositoryPath();
      if (repositoryPath) {
        const relativePath = getRelativePath(repositoryPath, filePath);
        const content = await GitService.getFileContentAtCommit(repositoryPath, relativePath, commit.sha);
        setHistoricalContent(content);
      }
    } catch (err) {
      console.error('Failed to load historical content:', err);
      setHistoricalContent(null);
    } finally {
      setIsLoadingHistory(false);
    }
  };

  const handleRestoreVersion = () => {
    if (historicalContent !== null) {
      setContent(historicalContent);
      setHasChanges(true);
      setShowHistoryModal(false);
      setSelectedCommit(null);
      setHistoricalContent(null);
    }
  };

  const clearHistoryDetail = () => {
    setSelectedCommit(null);
    setHistoricalContent(null);
  };

  /** From commit preview: back returns to the list. From list: closes the modal. */
  const handleHistoryModalDismissPress = () => {
    if (selectedCommit) {
      clearHistoryDetail();
      return;
    }
    setShowHistoryModal(false);
    setSelectedCommit(null);
    setHistoricalContent(null);
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

  // Custom render rules for wiki links and local images
  const renderRules = {
    image: (node: any, _children: any, _parent: any, styles: any) => {
      const { src, alt } = node.attributes;
      // Unwrap the synapse-local:// placeholder to recover the real file:// URI
      const uri = src?.startsWith(LOCAL_IMAGE_SCHEME)
        ? src.slice(LOCAL_IMAGE_SCHEME.length)
        : src;
      return (
        <Image
          key={node.key}
          source={{ uri }}
          accessible={!!alt}
          accessibilityLabel={alt}
          style={[styles._VIEW_SAFE_image, { width: '100%', height: 200, resizeMode: 'contain' }]}
        />
      );
    },
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

  const previewContent = preparePreviewContent(content, filePath);

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
              allowedImageHandlers={['data:image/png;base64', 'data:image/gif;base64', 'data:image/jpeg;base64', 'https://', 'http://', LOCAL_IMAGE_SCHEME]}
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

        <View
          style={[
            styles.editorFooter,
            {
              borderTopColor: theme.colors.border,
              backgroundColor: theme.colors.background,
              paddingBottom: Math.max(insets.bottom, 10),
            },
          ]}
        >
          <View style={styles.editorFooterLeft}>
            {fileHistory.length > 0 ? (
              <TouchableOpacity
                style={styles.editorFooterHistoryBtn}
                onPress={handleViewHistory}
                testID="view-history-button"
                accessibilityRole="button"
                accessibilityLabel="Version history"
              >
                <MaterialIcons name="history" size={22} color={theme.colors.primary} style={{ marginRight: 6 }} />
                <Text style={[styles.editorFooterHistoryLabel, { color: theme.colors.primary }]}>
                  History
                </Text>
              </TouchableOpacity>
            ) : null}
          </View>
          <View style={styles.editorFooterRight}>
            <TouchableOpacity
              testID="save-button"
              style={[
                styles.editorFooterSaveButton,
                { backgroundColor: hasChanges ? theme.colors.primary : theme.colors.border },
              ]}
              onPressIn={() => {
                shouldRestoreEditorFocusRef.current = textInputRef.current?.isFocused() ?? false;
              }}
              onPress={handleSave}
              disabled={!hasChanges || isSaving}
              accessibilityRole="button"
              accessibilityLabel="Save note"
            >
              {isSaving ? (
                <ActivityIndicator size="small" color={theme.colors.background} />
              ) : (
                <View style={styles.editorFooterSaveInner}>
                  <MaterialIcons name="save" size={18} color={theme.colors.background} style={{ marginRight: 6 }} />
                  <Text style={[styles.editorFooterSaveLabel, { color: theme.colors.background }]}>Save</Text>
                </View>
              )}
            </TouchableOpacity>
          </View>
        </View>
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

      {/* History Modal */}
      {showHistoryModal && (
        <View style={styles.historyModalOverlay}>
          <View
            style={[
              styles.historyModal,
              {
                backgroundColor: theme.colors.card,
                height: Math.min(Dimensions.get('window').height * 0.88, 780),
              },
            ]}
          >
            <View style={styles.historyModalHeaderRow}>
              <Text
                style={[styles.historyModalTitle, { color: theme.colors.text, flex: 1 }]}
                numberOfLines={1}
              >
                {selectedCommit ? 'Historical version' : 'Version history'}
              </Text>
              <TouchableOpacity
                onPress={handleHistoryModalDismissPress}
                testID="history-modal-close"
                accessibilityRole="button"
                accessibilityLabel={selectedCommit ? 'Back to version list' : 'Close'}
                hitSlop={{ top: 12, bottom: 12, left: 12, right: 12 }}
              >
                <MaterialIcons
                  name={selectedCommit ? 'arrow-back' : 'close'}
                  size={24}
                  color={theme.colors.text}
                />
              </TouchableOpacity>
            </View>

            {selectedCommit ? (
              <View style={styles.historyDetailColumn}>
                <View style={[styles.historyCommitMeta, { borderBottomColor: theme.colors.border }]}>
                  <Text style={[styles.historyCommitMetaMessage, { color: theme.colors.text }]} numberOfLines={3}>
                    {selectedCommit.message}
                  </Text>
                  <Text style={[styles.historyCommitMetaDate, { color: theme.colors.text + '99' }]}>
                    {selectedCommit.date.toLocaleDateString(undefined, {
                      year: 'numeric',
                      month: 'short',
                      day: 'numeric',
                    })}
                  </Text>
                </View>
                <View style={styles.historyPreviewScrollWrap}>
                  <ScrollView
                    style={styles.historyPreviewScrollInner}
                    contentContainerStyle={styles.historyPreviewContent}
                    keyboardShouldPersistTaps="handled"
                    nestedScrollEnabled
                    bounces
                    showsVerticalScrollIndicator
                  >
                    {isLoadingHistory ? (
                      <ActivityIndicator size="large" color={theme.colors.primary} style={{ marginTop: 24 }} />
                    ) : historicalContent ? (
                      <Markdown style={historyMdStyles}>
                        {preparePreviewContent(historicalContent, filePath)}
                      </Markdown>
                    ) : (
                      <Text style={[styles.historyPreviewErrorText, { color: theme.colors.text }]}>
                        Failed to load historical version
                      </Text>
                    )}
                  </ScrollView>
                </View>

                <TouchableOpacity
                  style={[styles.restoreButton, { backgroundColor: theme.colors.primary }]}
                  onPress={handleRestoreVersion}
                  disabled={historicalContent === null}
                  accessibilityRole="button"
                  accessibilityLabel="Restore this version"
                >
                  <MaterialIcons name="restore" size={20} color="#FFFFFF" style={{ marginRight: 8 }} />
                  <Text style={styles.restoreButtonText}>Restore this version</Text>
                </TouchableOpacity>
              </View>
            ) : (
              <ScrollView
                style={styles.historyListScroll}
                contentContainerStyle={styles.historyListContent}
                keyboardShouldPersistTaps="handled"
              >
                {fileHistory.length === 0 ? (
                  <Text style={[styles.historyEmptyText, { color: theme.colors.text + '80' }]}>
                    No history available for this file
                  </Text>
                ) : (
                  fileHistory.map((commit, index) => (
                    <TouchableOpacity
                      key={commit.sha}
                      style={[
                        styles.historyListItem,
                        { borderBottomColor: theme.colors.border },
                        index === fileHistory.length - 1 && { borderBottomWidth: 0 },
                      ]}
                      onPress={() => handleSelectCommit(commit)}
                    >
                      <MaterialIcons name="commit" size={20} color={theme.colors.primary} />
                      <View style={styles.historyItemContent}>
                        <Text style={[styles.historyItemMessage, { color: theme.colors.text }]} numberOfLines={2}>
                          {commit.message}
                        </Text>
                        <Text style={[styles.historyItemDate, { color: theme.colors.text + '80' }]}>
                          {commit.date.toLocaleDateString(undefined, {
                            year: 'numeric',
                            month: 'short',
                            day: 'numeric',
                          })}
                        </Text>
                      </View>
                      <MaterialIcons name="chevron-right" size={20} color={theme.colors.text + '40'} />
                    </TouchableOpacity>
                  ))
                )}
              </ScrollView>
            )}
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
    marginRight: 4,
    justifyContent: 'center',
    alignItems: 'center',
  },
  editorFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 10,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  editorFooterLeft: {
    flex: 1,
    alignItems: 'flex-start',
    justifyContent: 'center',
  },
  editorFooterRight: {
    flex: 1,
    alignItems: 'flex-end',
    justifyContent: 'center',
  },
  editorFooterHistoryBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingRight: 12,
  },
  editorFooterHistoryLabel: {
    fontSize: 16,
    fontWeight: '600',
    letterSpacing: -0.2,
  },
  editorFooterSaveButton: {
    paddingHorizontal: 18,
    paddingVertical: 10,
    borderRadius: 12,
    minWidth: 96,
    alignItems: 'center',
    justifyContent: 'center',
  },
  editorFooterSaveInner: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  editorFooterSaveLabel: {
    fontSize: 15,
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
    marginLeft: 2,
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
    flexWrap: 'wrap',
  },
  historyModalOverlay: {
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
  historyModal: {
    width: '92%',
    maxHeight: '85%',
    borderRadius: 16,
    padding: 16,
    overflow: 'hidden',
    flexDirection: 'column',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 8,
  },
  historyModalHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
    minHeight: 36,
    flexShrink: 0,
  },
  historyModalTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginRight: 8,
  },
  historyDetailColumn: {
    flex: 1,
    minHeight: 0,
    flexDirection: 'column',
  },
  historyCommitMeta: {
    paddingBottom: 10,
    marginBottom: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexGrow: 0,
    flexShrink: 0,
  },
  historyCommitMetaMessage: {
    fontSize: 13,
    fontWeight: '600',
    marginBottom: 4,
    lineHeight: 18,
  },
  historyCommitMetaDate: {
    fontSize: 12,
  },
  historyPreviewScrollWrap: {
    flex: 1,
    minHeight: 0,
    flexShrink: 1,
    overflow: 'hidden',
  },
  historyPreviewScrollInner: {
    flex: 1,
  },
  historyPreviewContent: {
    paddingBottom: 12,
    paddingHorizontal: 4,
    flexGrow: 1,
  },
  historyPreviewErrorText: {
    marginTop: 16,
    fontSize: 13,
  },
  historyListScroll: {
    flex: 1,
    minHeight: 0,
    flexShrink: 1,
    overflow: 'hidden',
  },
  historyListContent: {
    paddingBottom: 8,
  },
  historyListItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 8,
    borderBottomWidth: 1,
  },
  historyItemContent: {
    flex: 1,
    marginLeft: 12,
    marginRight: 8,
  },
  historyItemMessage: {
    fontSize: 15,
    fontWeight: '500',
    marginBottom: 2,
  },
  historyItemDate: {
    fontSize: 12,
  },
  historyEmptyText: {
    fontSize: 14,
    textAlign: 'center',
    paddingVertical: 24,
  },
  restoreButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 22,
    paddingVertical: 14,
    borderRadius: 12,
    marginTop: 10,
    flexGrow: 0,
    flexShrink: 0,
  },
  restoreButtonText: {
    fontSize: 16,
    fontWeight: '700',
    color: '#FFFFFF',
  },
});
