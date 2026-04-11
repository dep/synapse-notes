import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Modal,
  Animated,
  Dimensions,
  FlatList,
  ActivityIndicator,
  Alert,
  TextInput,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { MaterialIcons } from '@expo/vector-icons';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useTheme } from '../theme/ThemeContext';
import { FileSystemService, FileNode } from '../services/FileSystemService';
import { PinningStorage, PinnedItem } from '../services/PinningStorage';
import { SettingsStorage } from '../services/SettingsStorage';
import { TemplateStorage } from '../services/TemplateStorage';
import { GitService } from '../services/gitService';
import { OnboardingStorage } from '../services/onboardingStorage';
import { emitRepositoryRefresh } from '../services/repositoryEvents';

interface FileDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  onFileSelect: (path: string) => void;
  onNewNote: () => void;
  onNewFolder: () => void;
  onTodayNote: () => void;
  vaultPath: string;
  repoName?: string;
  activeFilePath?: string;
  showHamburger?: boolean;
}

type ViewMode = 'tree' | 'flat';
type SortOption = 'name-asc' | 'name-desc' | 'modified-asc' | 'modified-desc';

const STORAGE_KEYS = {
  viewMode: '@filedrawer_viewmode',
  sortOption: '@filedrawer_sortoption',
};

// Flat row type used by FlatList for tree mode virtualization
type TreeRow = { node: FileNode; level: number };

// ─── Memoized row components ───────────────────────────────────────────────

interface FolderRowProps {
  node: FileNode;
  level: number;
  isExpanded: boolean;
  isLoading: boolean;
  templatesDirectory: string;
  theme: any;
  onPress: (path: string, hasLoadedChildren: boolean) => void;
  onLongPress: (node: FileNode) => void;
}

const FolderRow = React.memo(({
  node, level, isExpanded, isLoading, templatesDirectory, theme, onPress, onLongPress,
}: FolderRowProps) => {
  const isTemplatesFolder = node.name === templatesDirectory;
  return (
    <View>
      <TouchableOpacity
        style={[styles.folderItem, { paddingLeft: 16 + level * 16 }]}
        onPress={() => onPress(node.path, Array.isArray(node.children))}
        onLongPress={() => onLongPress(node)}
        disabled={isLoading}
      >
        {isLoading ? (
          <ActivityIndicator size="small" color={theme.colors.text} style={styles.folderIcon} />
        ) : (
          <MaterialIcons
            name={isExpanded ? 'folder-open' : 'folder'}
            size={22}
            color="#f59e0b"
            style={styles.folderIcon}
          />
        )}
        <Text
          style={[styles.folderName, { color: theme.colors.text }, isLoading && { opacity: 0.7 }]}
          numberOfLines={1}
        >
          {node.name}
        </Text>
        {isTemplatesFolder && (
          <View style={[styles.templatesChip, { backgroundColor: theme.colors.primary + '20' }]}>
            <Text style={[styles.templatesChipText, { color: theme.colors.primary }]}>
              templates
            </Text>
          </View>
        )}
      </TouchableOpacity>
    </View>
  );
});

interface FileRowProps {
  node: FileNode;
  level: number;
  isActive: boolean;
  theme: any;
  onPress: (path: string) => void;
  onLongPress: (node: FileNode) => void;
}

const FileRow = React.memo(({ node, level, isActive, theme, onPress, onLongPress }: FileRowProps) => (
  <TouchableOpacity
    style={[
      styles.fileItem,
      { paddingLeft: 16 + level * 16 },
      isActive && { backgroundColor: theme.colors.primary + '20' },
    ]}
    onPress={() => onPress(node.path)}
    onLongPress={() => onLongPress(node)}
    testID={isActive ? 'file-item-active' : undefined}
  >
    <MaterialIcons
      name="insert-drive-file"
      size={20}
      color={isActive ? theme.colors.primary : theme.colors.text}
      style={styles.fileIcon}
    />
    <Text
      style={[
        styles.fileName,
        { color: theme.colors.text },
        isActive && { color: theme.colors.primary, fontWeight: '600' },
      ]}
      numberOfLines={1}
    >
      {node.name}
    </Text>
  </TouchableOpacity>
));

interface PinnedRowProps {
  item: PinnedItem;
  isActive: boolean;
  theme: any;
  onPress: (item: PinnedItem) => void;
  onLongPress: (item: PinnedItem) => void;
}

const PinnedRow = React.memo(({ item, isActive, theme, onPress, onLongPress }: PinnedRowProps) => (
  <TouchableOpacity
    style={[styles.pinnedItem, isActive && { backgroundColor: theme.colors.primary + '20' }]}
    onPress={() => onPress(item)}
    onLongPress={() => onLongPress(item)}
  >
    <MaterialIcons
      name={item.isFolder ? 'folder' : 'push-pin'}
      size={18}
      color={isActive ? theme.colors.primary : item.isFolder ? '#f59e0b' : theme.colors.text + '80'}
      style={styles.pinnedIcon}
    />
    <Text
      style={[
        styles.pinnedName,
        { color: theme.colors.text },
        isActive && { color: theme.colors.primary, fontWeight: '600' },
      ]}
      numberOfLines={1}
    >
      {item.name}
    </Text>
  </TouchableOpacity>
));

interface SearchResultRowProps {
  result: { file: FileNode; lineNumber: number; lineText: string; matchIndex: number };
  index: number;
  isActive: boolean;
  theme: any;
  onPress: (path: string) => void;
}

const SearchResultRow = React.memo(({ result, index, isActive, theme, onPress }: SearchResultRowProps) => (
  <TouchableOpacity
    style={[
      styles.searchResultItem,
      { borderBottomColor: theme.colors.border },
      isActive && styles.searchResultItemActive,
    ]}
    onPress={() => onPress(result.file.path)}
    testID={`search-result-${index}`}
  >
    <View style={styles.searchResultHeader}>
      <MaterialIcons name="description" size={16} color={theme.colors.primary} />
      <Text style={[styles.searchResultFileName, { color: theme.colors.text }]} numberOfLines={1}>
        {result.file.name.replace(/\.md$/, '')}
      </Text>
      <Text style={[styles.searchResultLineNumber, { color: theme.colors.text + '50' }]}>
        Line {result.lineNumber}
      </Text>
    </View>
    <Text style={[styles.searchResultPreview, { color: theme.colors.text + '80' }]} numberOfLines={2}>
      {result.lineText}
    </Text>
  </TouchableOpacity>
));

export function FileDrawer({
  isOpen: initialIsOpen,
  onClose,
  onFileSelect,
  onNewNote,
  onNewFolder,
  onTodayNote,
  vaultPath,
  repoName,
  activeFilePath,
  showHamburger = true,
}: FileDrawerProps) {
  const { theme } = useTheme();
  const insets = useSafeAreaInsets();
  const [isOpen, setIsOpen] = useState(initialIsOpen);
  const [viewMode, setViewMode] = useState<ViewMode>('tree');
  const [sortOption, setSortOption] = useState<SortOption>('name-asc');
  const [hasLoadedPreferences, setHasLoadedPreferences] = useState(false);
  const [files, setFiles] = useState<FileNode[]>([]);
  const [flatFiles, setFlatFiles] = useState<FileNode[]>([]);
  const [expandedFolders, setExpandedFolders] = useState<Set<string>>(new Set());
  const [isLoading, setIsLoading] = useState(false);
  const [isLoadingFlat, setIsLoadingFlat] = useState(false);
  const [loadingFolder, setLoadingFolder] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [lastLoadedVaultPath, setLastLoadedVaultPath] = useState<string | null>(null);
  const [pinnedItems, setPinnedItems] = useState<PinnedItem[]>([]);
  const [fileFilters, setFileFilters] = useState<{ fileExtensionFilter: string; hiddenFileFolderFilter: string }>({ 
    fileExtensionFilter: '*.md, *.txt', 
    hiddenFileFolderFilter: '' 
  });
  const [templatesDirectory, setTemplatesDirectory] = useState<string>('templates');
  const slideAnim = useState(new Animated.Value(-Dimensions.get('window').width * 0.8))[0];
  
  // Vault-wide search state
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<{ file: FileNode; lineNumber: number; lineText: string; matchIndex: number }[]>([]);
  const [isSearching, setIsSearching] = useState(false);

  const loadPreferences = useCallback(async () => {
    setHasLoadedPreferences(false);
    try {
      const savedViewMode = await AsyncStorage.getItem(STORAGE_KEYS.viewMode);
      const savedSortOption = await AsyncStorage.getItem(STORAGE_KEYS.sortOption);
      
      if (savedViewMode) {
        setViewMode(savedViewMode as ViewMode);
      }
      if (savedSortOption) {
        setSortOption(savedSortOption as SortOption);
      }
    } catch (error) {
      console.error('[FileDrawer] Failed to load preferences:', error);
    } finally {
      setHasLoadedPreferences(true);
    }
  }, []);

  // Load saved preferences and file filters on mount
  useEffect(() => {
    const loadFileFilters = async () => {
      try {
        const settings = await SettingsStorage.getAllFileBrowserSettings();
        setFileFilters(settings);
      } catch (error) {
        console.error('[FileDrawer] Failed to load file filters:', error);
      }
    };

    const loadTemplatesDirectory = async () => {
      try {
        const dir = await TemplateStorage.getTemplatesDirectory();
        setTemplatesDirectory(dir);
      } catch (error) {
        console.error('[FileDrawer] Failed to load templates directory:', error);
      }
    };
    
    loadPreferences();
    loadFileFilters();
    loadTemplatesDirectory();
  }, [loadPreferences]);

  // Reload preferences when drawer opens (in case they changed or component remounted)
  useEffect(() => {
    if (isOpen) {
      loadPreferences();
    }
  }, [isOpen, loadPreferences]);

  // Save view mode when it changes
  useEffect(() => {
    if (!hasLoadedPreferences) {
      return;
    }
    AsyncStorage.setItem(STORAGE_KEYS.viewMode, viewMode).catch(error => {
      console.error('[FileDrawer] Failed to save view mode:', error);
    });
  }, [viewMode, hasLoadedPreferences]);

  // Save sort option when it changes
  useEffect(() => {
    if (!hasLoadedPreferences) {
      return;
    }
    AsyncStorage.setItem(STORAGE_KEYS.sortOption, sortOption).catch(error => {
      console.error('[FileDrawer] Failed to save sort option:', error);
    });
  }, [sortOption, hasLoadedPreferences]);

  // Sync with parent isOpen prop
  useEffect(() => {
    setIsOpen(initialIsOpen);
  }, [initialIsOpen]);

  // Clear files when vault path changes and track the change
  useEffect(() => {
    setFiles([]);
    setFlatFiles([]);
    setExpandedFolders(new Set());
    setLastUpdated(null);
    setLastLoadedVaultPath(null);
    loadPinnedItems();
    
    // Reload templates directory when vault changes
    const loadTemplatesDir = async () => {
      try {
        const dir = await TemplateStorage.getTemplatesDirectory();
        setTemplatesDirectory(dir);
      } catch (error) {
        console.error('[FileDrawer] Failed to reload templates directory:', error);
      }
    };
    loadTemplatesDir();
  }, [vaultPath]);

  // Load pinned items
  const loadPinnedItems = useCallback(async () => {
    try {
      const items = await PinningStorage.getPinnedItems(vaultPath);
      setPinnedItems(items);
    } catch (error) {
      console.error('[FileDrawer] Failed to load pinned items:', error);
    }
  }, [vaultPath]);

  // Animate drawer and load files when opened
  useEffect(() => {
    if (isOpen) {
      Animated.timing(slideAnim, {
        toValue: 0,
        duration: 250,
        useNativeDriver: true,
      }).start();
      // Always refresh when drawer opens so new notes are visible
      loadRootFiles(true);
    } else {
      Animated.timing(slideAnim, {
        toValue: -Dimensions.get('window').width * 0.8,
        duration: 250,
        useNativeDriver: true,
      }).start();
    }
  }, [isOpen, vaultPath]);

  // Eagerly pre-load flat file list whenever the drawer opens so switching to
  // Files view is instant. Always force-refresh so new notes are visible.
  useEffect(() => {
    if (isOpen && !isLoadingFlat) {
      loadFlatFiles(true);
    }
  }, [isOpen, vaultPath]);

  const updateNodeChildren = useCallback((nodes: FileNode[], targetPath: string, children: FileNode[]): FileNode[] => {
    return nodes.map((node) => {
      if (node.path === targetPath) {
        return { ...node, children };
      }
      if (node.children) {
        return { ...node, children: updateNodeChildren(node.children, targetPath, children) };
      }
      return node;
    });
  }, []);

  const loadRootFiles = useCallback(async (forceRefresh = false) => {
    console.log('[FileDrawer] Loading root files from:', vaultPath, forceRefresh ? '(forced refresh)' : '');
    if (!forceRefresh && lastLoadedVaultPath === vaultPath) {
      console.log('[FileDrawer] Already loaded for this vault, skipping');
      return;
    }

    setIsLoading(true);
    try {
      const treeFiles = await FileSystemService.listDirectory(vaultPath, fileFilters);
      console.log('[FileDrawer] Loaded', treeFiles.length, 'root entries');

      setFiles(treeFiles);
      setLastUpdated(new Date());
      setLastLoadedVaultPath(vaultPath);
    } catch (error) {
      console.error('[FileDrawer] Failed to load files:', error);
      console.error('[FileDrawer] vaultPath was:', vaultPath);
    } finally {
      setIsLoading(false);
    }
  }, [vaultPath, lastLoadedVaultPath, fileFilters]);

  // Sync with git and then refresh file list
  const syncAndRefreshFiles = useCallback(async () => {
    console.log('[FileDrawer] Refreshing from remote...');
    
    setIsLoading(true);
    try {
      // First sync with git to pull down any remote changes
      const repositoryPath = await OnboardingStorage.getActiveRepositoryPath();
      if (repositoryPath) {
        try {
          await GitService.refreshRemote(repositoryPath);
          await emitRepositoryRefresh(repositoryPath);
          console.log('[FileDrawer] Remote refresh completed');
        } catch (syncError) {
          console.error('[FileDrawer] Remote refresh failed (will still refresh local files):', syncError);
          // Don't block file refresh if sync fails
        }
      }
      
      // Then refresh the file list
      await loadRootFiles(true);
      await loadPinnedItems();
    } catch (error) {
      console.error('[FileDrawer] Error during sync and refresh:', error);
    } finally {
      setIsLoading(false);
    }
  }, [loadRootFiles, loadPinnedItems]);

  const loadFlatFiles = useCallback(async (forceRefresh = false) => {
    if (!forceRefresh && flatFiles.length > 0) {
      return;
    }

    setIsLoadingFlat(true);
    try {
      const flatFileList = await FileSystemService.getFlatFileList(vaultPath, fileFilters);
      setFlatFiles(flatFileList);
    } catch (error) {
      console.error('[FileDrawer] Failed to load flat files:', error);
    } finally {
      setIsLoadingFlat(false);
    }
  }, [vaultPath, flatFiles.length, fileFilters]);

  const sortFiles = useCallback((nodes: FileNode[]): FileNode[] => {
    const sorted = [...nodes].sort((a, b) => {
      // Folders always before files
      if (a.isDirectory !== b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      switch (sortOption) {
        case 'name-asc':
          return a.name.localeCompare(b.name);
        case 'name-desc':
          return b.name.localeCompare(a.name);
        case 'modified-asc':
          return (a.modifiedAt?.getTime() || 0) - (b.modifiedAt?.getTime() || 0);
        case 'modified-desc':
          return (b.modifiedAt?.getTime() || 0) - (a.modifiedAt?.getTime() || 0);
        default:
          return 0;
      }
    });

    // Recursively sort children for tree view
    return sorted.map(node => ({
      ...node,
      children: node.isDirectory && node.children ? sortFiles(node.children) : node.children,
    }));
  }, [sortOption]);

  const sortedFiles = useMemo(() => sortFiles(files), [files, sortFiles]);
  const sortedFlatFiles = useMemo(() => sortFiles(flatFiles), [flatFiles, sortFiles]);

  // Flatten the nested tree into a single array for FlatList virtualization.
  // Only includes folders that are currently expanded.
  const flattenTree = useCallback((nodes: FileNode[], level: number = 0): TreeRow[] => {
    const rows: TreeRow[] = [];
    for (const node of nodes) {
      rows.push({ node, level });
      if (node.isDirectory && expandedFolders.has(node.path) && node.children) {
        rows.push(...flattenTree(node.children, level + 1));
      }
    }
    return rows;
  }, [expandedFolders]);

  const treeRows = useMemo(() => flattenTree(sortedFiles), [sortedFiles, flattenTree]);
  const flatRows = useMemo<TreeRow[]>(() => sortedFlatFiles.map(node => ({ node, level: 0 })), [sortedFlatFiles]);

  // Manual search execution
  const handleSearch = useCallback(async () => {
    if (!searchQuery.trim() || !vaultPath) {
      setSearchResults([]);
      return;
    }

    setIsSearching(true);
    
    try {
      // Get all markdown files
      const allFiles = await FileSystemService.getFlatFileList(vaultPath, {
        fileExtensionFilter: '*.md',
        hiddenFileFolderFilter: '.git',
      });

      const results: { file: FileNode; lineNumber: number; lineText: string; matchIndex: number }[] = [];
      const lowerQuery = searchQuery.toLowerCase();

      // Search through each file
      for (const file of allFiles) {
        try {
          const content = await FileSystemService.readFile(file.path);
          const lines = content.split('\n');
          
          lines.forEach((line, index) => {
            if (line.toLowerCase().includes(lowerQuery)) {
              results.push({
                file,
                lineNumber: index + 1,
                lineText: line.trim().substring(0, 100), // Limit preview length
                matchIndex: line.toLowerCase().indexOf(lowerQuery),
              });
            }
          });
        } catch (err) {
          console.warn(`[FileDrawer] Error reading file ${file.path}:`, err);
        }
      }

      // Sort results by file modified date (descending - most recent first)
      results.sort((a, b) => {
        const dateA = a.file.modifiedAt?.getTime() || 0;
        const dateB = b.file.modifiedAt?.getTime() || 0;
        return dateB - dateA;
      });

      setSearchResults(results);
    } catch (error) {
      console.error('[FileDrawer] Search error:', error);
    } finally {
      setIsSearching(false);
    }
  }, [searchQuery, vaultPath]);

  const clearSearch = () => {
    setSearchQuery('');
    setSearchResults([]);
    setIsSearching(false);
  };

  const openDrawer = useCallback(() => {
    setIsOpen(true);
  }, []);

  const closeDrawer = useCallback(() => {
    setIsOpen(false);
    onClose();
  }, [onClose]);

  const handleFileSelect = useCallback((path: string) => {
    onFileSelect(path);
    closeDrawer();
  }, [onFileSelect, closeDrawer]);

  const handleNewNote = () => {
    setFiles([]);
    setFlatFiles([]);
    setExpandedFolders(new Set());
    setLastUpdated(null);
    setLastLoadedVaultPath(null);
    onNewNote();
  };

  const handleTodayNote = () => {
    setFiles([]);
    setFlatFiles([]);
    setExpandedFolders(new Set());
    setLastUpdated(null);
    setLastLoadedVaultPath(null);
    onTodayNote();
    closeDrawer();
  };

  const handlePinItem = async (path: string, name: string, isFolder: boolean) => {
    try {
      await PinningStorage.pinItem(path, name, isFolder, vaultPath);
      await loadPinnedItems();
    } catch (error) {
      console.error('[FileDrawer] Failed to pin item:', error);
      Alert.alert('Error', 'Failed to pin item');
    }
  };

  const handleUnpinItem = async (path: string) => {
    try {
      await PinningStorage.unpinItem(path, vaultPath);
      await loadPinnedItems();
    } catch (error) {
      console.error('[FileDrawer] Failed to unpin item:', error);
      Alert.alert('Error', 'Failed to unpin item');
    }
  };

  const showPinContextMenu = useCallback(async (node: FileNode) => {
    const isPinned = await PinningStorage.isPinned(node.path, vaultPath);
    
    const buttons: any[] = [
      {
        text: isPinned ? 'Unpin' : 'Pin',
        onPress: () => {
          if (isPinned) {
            handleUnpinItem(node.path);
          } else {
            handlePinItem(node.path, node.name, node.isDirectory);
          }
        },
      },
    ];

    // Add delete option for files only
    if (!node.isDirectory) {
      buttons.push({
        text: 'Delete',
        style: 'destructive',
        onPress: () => handleDeleteFile(node),
      });
    }

    buttons.push(
      {
        text: 'Open',
        onPress: () => handleFileSelect(node.path),
      },
      {
        text: 'Cancel',
        style: 'cancel',
      }
    );
    
    Alert.alert(
      node.name,
      undefined,
      buttons
    );
  }, [vaultPath, handlePinItem, handleUnpinItem, handleFileSelect]);

  const handleDeleteFile = useCallback((node: FileNode) => {
    Alert.alert(
      'Delete File?',
      `Are you sure you want to delete "${node.name}"? This action cannot be undone.`,
      [
        {
          text: 'Cancel',
          style: 'cancel',
        },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              await FileSystemService.deleteFile(node.path);
              
              // If the deleted file was the active file, clear it
              if (node.path === activeFilePath && onFileSelect) {
                onFileSelect('');
              }
              
              // Sync with git to push the deletion
              const repositoryPath = await OnboardingStorage.getActiveRepositoryPath();
              if (repositoryPath) {
                try {
                  // Get the relative path for the deleted file
                  const relativePath = node.path.replace(repositoryPath, '').replace(/^\/+/, '');
                  await GitService.sync(repositoryPath, [relativePath]);
                  console.log('[FileDrawer] File deletion synced to git');
                } catch (syncError) {
                  console.error('[FileDrawer] Failed to sync file deletion:', syncError);
                  // Don't show error to user, deletion succeeded even if sync failed
                }
              }
              
              // Refresh the file list
              await loadRootFiles(true);
              
              // Also refresh pinned items in case the deleted file was pinned
              await loadPinnedItems();
            } catch (error) {
              console.error('[FileDrawer] Failed to delete file:', error);
              Alert.alert('Error', 'Failed to delete file');
            }
          },
        },
      ]
    );
  }, [activeFilePath, onFileSelect, loadRootFiles, loadPinnedItems]);

  const toggleFolder = useCallback(async (path: string, hasLoadedChildren: boolean) => {
    const isExpanding = !expandedFolders.has(path);
    
    if (isExpanding && !hasLoadedChildren) {
      setLoadingFolder(path);
      try {
        const children = await FileSystemService.listDirectory(path, fileFilters);
        setFiles((prev) => updateNodeChildren(prev, path, children));
      } catch (error) {
        console.error('[FileDrawer] Failed to load folder children:', error);
      } finally {
        setLoadingFolder(null);
      }
    }

    setExpandedFolders(prev => {
      const newSet = new Set(prev);
      if (newSet.has(path)) {
        newSet.delete(path);
      } else {
        newSet.add(path);
      }
      return newSet;
    });
  }, [expandedFolders, fileFilters, updateNodeChildren]);

  const toggleViewMode = useCallback(() => {
    const next = viewMode === 'tree' ? 'flat' : 'tree';
    if (next === 'flat' && flatFiles.length === 0) {
      loadFlatFiles();
    }
    setViewMode(next);
  }, [viewMode, flatFiles.length, loadFlatFiles]);

  // FlatList renderItem for the virtualized file tree / flat list
  const renderTreeRow = useCallback(({ item }: { item: TreeRow }) => {
    const { node, level } = item;
    if (node.isDirectory) {
      return (
        <FolderRow
          node={node}
          level={level}
          isExpanded={expandedFolders.has(node.path)}
          isLoading={loadingFolder === node.path}
          templatesDirectory={templatesDirectory}
          theme={theme}
          onPress={toggleFolder}
          onLongPress={showPinContextMenu}
        />
      );
    }
    return (
      <FileRow
        node={node}
        level={level}
        isActive={node.path === activeFilePath}
        theme={theme}
        onPress={handleFileSelect}
        onLongPress={showPinContextMenu}
      />
    );
  }, [expandedFolders, loadingFolder, templatesDirectory, theme, toggleFolder, showPinContextMenu, activeFilePath, handleFileSelect]);

  const handlePinnedPress = useCallback((item: PinnedItem) => {
    if (item.isFolder) {
      toggleFolder(item.path, false);
    } else {
      handleFileSelect(item.path);
    }
  }, [toggleFolder, handleFileSelect]);

  const handlePinnedLongPress = useCallback((item: PinnedItem) => {
    Alert.alert(
      item.name,
      undefined,
      [
        { text: 'Unpin', onPress: () => handleUnpinItem(item.path) },
        {
          text: 'Open',
          onPress: () => {
            if (item.isFolder) {
              toggleFolder(item.path, false);
            } else {
              handleFileSelect(item.path);
            }
          },
        },
        { text: 'Cancel', style: 'cancel' },
      ]
    );
  }, [toggleFolder, handleFileSelect, handleUnpinItem]);

  const renderPinnedRow = useCallback(({ item }: { item: PinnedItem }) => (
    <PinnedRow
      item={item}
      isActive={item.path === activeFilePath}
      theme={theme}
      onPress={handlePinnedPress}
      onLongPress={handlePinnedLongPress}
    />
  ), [activeFilePath, theme, handlePinnedPress, handlePinnedLongPress]);

  const renderSearchRow = useCallback(({ item, index }: { item: typeof searchResults[0]; index: number }) => (
    <SearchResultRow
      result={item}
      index={index}
      isActive={item.file.path === activeFilePath}
      theme={theme}
      onPress={handleFileSelect}
    />
  ), [activeFilePath, theme, handleFileSelect, searchResults]);

  return (
    <>
      {/* Hamburger Button */}
      {showHamburger && (
        <TouchableOpacity
          style={styles.hamburgerButton}
          onPress={openDrawer}
          testID="hamburger-button"
        >
          <MaterialIcons name="menu" size={28} color={theme.colors.text} />
        </TouchableOpacity>
      )}

      {/* Drawer Modal */}
      <Modal
        visible={isOpen}
        transparent={true}
        animationType="none"
        onRequestClose={closeDrawer}
      >
        <View style={styles.modalContainer}>
          {/* Overlay */}
          <TouchableOpacity
            style={styles.overlay}
            onPress={closeDrawer}
            testID="drawer-overlay"
          />

          {/* Drawer Content */}
          <Animated.View
            style={[
              styles.drawer,
              {
                backgroundColor: theme.colors.card,
                transform: [{ translateX: slideAnim }],
                paddingTop: insets.top,
              },
            ]}
            testID="file-drawer"
          >
            {/* Header */}
            <View style={[styles.header, { borderBottomColor: theme.colors.border }]}>
              <View style={styles.headerTitleContainer}>
                <Text style={[styles.headerTitle, { color: theme.colors.text }]}>
                  Files
                </Text>
                {repoName ? (
                  <Text style={[styles.headerRepo, { color: theme.colors.text + '70' }]} numberOfLines={1}>
                    {repoName}
                  </Text>
                ) : null}
                {lastUpdated && (
                  <Text style={[styles.lastUpdatedText, { color: theme.colors.text + '50' }]}>
                    Updated {lastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                    {isLoading && ' • Loading...'}
                  </Text>
                )}
              </View>
              <View style={styles.headerButtons}>
                <TouchableOpacity
                  style={styles.refreshButton}
                  onPress={syncAndRefreshFiles}
                  disabled={isLoading}
                  testID="refresh-button"
                >
                  <MaterialIcons name="refresh" size={22} color={theme.colors.primary} />
                </TouchableOpacity>
                <TouchableOpacity
                  style={styles.viewToggleButton}
                  onPress={toggleViewMode}
                  testID="view-toggle-button"
                >
                  <MaterialIcons name={viewMode === 'tree' ? 'list' : 'account-tree'} size={22} color={theme.colors.primary} />
                </TouchableOpacity>
              </View>
            </View>

            {/* New Note Button */}
            <TouchableOpacity
              style={[styles.todayNoteButton, { backgroundColor: theme.colors.secondary, flexDirection: 'row', justifyContent: 'center' }]}
              onPress={handleTodayNote}
              testID="today-note-button"
            >
              <MaterialIcons name="today" size={20} color={theme.colors.background} style={{ marginRight: 8 }} />
              <Text style={[styles.todayNoteText, { color: theme.colors.background }]}>
                Today
              </Text>
            </TouchableOpacity>

            <View style={styles.newItemRow}>
              <TouchableOpacity
                style={[styles.newItemButton, { backgroundColor: theme.colors.primary }]}
                onPress={handleNewNote}
                testID="new-note-button"
              >
                <MaterialIcons name="add" size={18} color={theme.colors.background} />
                <Text style={[styles.newItemText, { color: theme.colors.background }]}>
                  Note
                </Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={[styles.newItemButton, { backgroundColor: theme.colors.primary }]}
                onPress={onNewFolder}
                testID="new-folder-button"
              >
                <MaterialIcons name="add" size={18} color={theme.colors.background} />
                <Text style={[styles.newItemText, { color: theme.colors.background }]}>
                  Folder
                </Text>
              </TouchableOpacity>
            </View>

            {/* Vault Search */}
            <View style={[styles.searchContainer, { backgroundColor: theme.colors.card }]}>
              <View style={styles.searchInputContainer}>
                <MaterialIcons name="search" size={20} color={theme.colors.text + '60'} style={styles.searchIcon} />
                <TextInput
                  testID="vault-search-input"
                  style={[styles.searchInput, { color: theme.colors.text }]}
                  value={searchQuery}
                  onChangeText={setSearchQuery}
                  placeholder="Search all notes..."
                  placeholderTextColor={theme.colors.text + '60'}
                  returnKeyType="search"
                  onSubmitEditing={handleSearch}
                />
                {searchQuery.length > 0 && (
                  <TouchableOpacity onPress={clearSearch} testID="clear-search-button">
                    <MaterialIcons name="close" size={20} color={theme.colors.text + '60'} />
                  </TouchableOpacity>
                )}
              </View>
              
              {/* Search Button */}
              <TouchableOpacity
                style={[styles.searchButton, { backgroundColor: theme.colors.primary }]}
                onPress={handleSearch}
                disabled={isSearching || !searchQuery.trim()}
                testID="search-button"
              >
                {isSearching ? (
                  <ActivityIndicator size="small" color={theme.colors.background} />
                ) : (
                  <>
                    <MaterialIcons name="search" size={18} color={theme.colors.background} />
                    <Text style={[styles.searchButtonText, { color: theme.colors.background }]}>
                      Search
                    </Text>
                  </>
                )}
              </TouchableOpacity>
              
              {/* Search Results */}
              {searchResults.length > 0 && (
                <View style={styles.searchResultsContainer}>
                  <Text style={[styles.searchResultsHeader, { color: theme.colors.text + '70' }]}>
                    {searchResults.length} match{searchResults.length !== 1 ? 'es' : ''}
                  </Text>
                  <FlatList
                    style={styles.searchResultsList}
                    testID="search-results-list"
                    data={searchResults}
                    keyExtractor={(result, index) => `${result.file.path}-${result.lineNumber}-${index}`}
                    renderItem={renderSearchRow}
                    removeClippedSubviews={true}
                    maxToRenderPerBatch={10}
                    windowSize={5}
                  />
                </View>
              )}
            </View>

            {/* Pinned Items */}
            {pinnedItems.length > 0 && (
              <View style={styles.pinnedSection}>
                <Text style={[styles.pinnedHeader, { color: theme.colors.text + '70' }]}>
                  PINNED
                </Text>
                <FlatList
                  data={pinnedItems}
                  keyExtractor={item => item.id}
                  renderItem={renderPinnedRow}
                  scrollEnabled={false}
                />
              </View>
            )}

            {/* Sort Controls */}
            <View style={styles.sortControlsContainer}>
              <View style={[styles.sortButtonGroup, { backgroundColor: theme.colors.border + '22', borderColor: theme.colors.border + '55' }]}>
                <TouchableOpacity
                  style={[
                    styles.sortGroupButton,
                    {
                      borderColor: sortOption.startsWith('name') ? theme.colors.primary + '55' : theme.colors.border + '40',
                    },
                    sortOption.startsWith('name') && { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 1 }, shadowOpacity: 0.1, shadowRadius: 2, elevation: 2 }
                  ]}
                  onPress={() => setSortOption(sortOption.startsWith('name') ? sortOption : 'name-asc')}
                >
                  <MaterialIcons name="sort-by-alpha" size={14} color={sortOption.startsWith('name') ? theme.colors.primary : theme.colors.text + '80'} style={{ marginRight: 4 }} />
                  <Text style={[styles.sortGroupText, { color: sortOption.startsWith('name') ? theme.colors.primary : theme.colors.text + '80', fontWeight: sortOption.startsWith('name') ? '600' : '400' }]}>Name</Text>
                </TouchableOpacity>
                <TouchableOpacity
                  style={[
                    styles.sortGroupButton,
                    {
                      borderColor: sortOption.startsWith('modified') ? theme.colors.primary + '55' : theme.colors.border + '40',
                    },
                    sortOption.startsWith('modified') && { backgroundColor: theme.colors.card, shadowColor: '#000', shadowOffset: { width: 0, height: 1 }, shadowOpacity: 0.1, shadowRadius: 2, elevation: 2 }
                  ]}
                  onPress={() => setSortOption(sortOption.startsWith('modified') ? sortOption : 'modified-desc')}
                >
                  <MaterialIcons name="access-time" size={14} color={sortOption.startsWith('modified') ? theme.colors.primary : theme.colors.text + '80'} style={{ marginRight: 4 }} />
                  <Text style={[styles.sortGroupText, { color: sortOption.startsWith('modified') ? theme.colors.primary : theme.colors.text + '80', fontWeight: sortOption.startsWith('modified') ? '600' : '400' }]}>Date</Text>
                </TouchableOpacity>
              </View>

              <TouchableOpacity
                style={[styles.sortDirectionButton, { backgroundColor: theme.colors.border + '22', borderColor: theme.colors.border + '55' }]}
                onPress={() => {
                  if (sortOption === 'name-asc') setSortOption('name-desc');
                  else if (sortOption === 'name-desc') setSortOption('name-asc');
                  else if (sortOption === 'modified-asc') setSortOption('modified-desc');
                  else if (sortOption === 'modified-desc') setSortOption('modified-asc');
                }}
              >
                <MaterialIcons name={sortOption.endsWith('asc') ? 'arrow-upward' : 'arrow-downward'} size={18} color={theme.colors.text} />
              </TouchableOpacity>
            </View>

            {/* File List */}
            {isLoading || isLoadingFlat ? (
              <View style={styles.loadingContainer}>
                <ActivityIndicator size="large" color={theme.colors.primary} />
                <Text style={[styles.loadingText, { color: theme.colors.text, marginTop: 12 }]}>
                  {isLoading ? 'Loading files...' : 'Loading all files...'}
                </Text>
              </View>
            ) : (
              <FlatList
                style={styles.fileList}
                data={viewMode === 'tree' ? treeRows : flatRows}
                keyExtractor={item => item.node.path}
                renderItem={renderTreeRow}
                removeClippedSubviews={true}
                maxToRenderPerBatch={15}
                updateCellsBatchingPeriod={50}
                windowSize={7}
                ListEmptyComponent={
                  <View style={styles.emptyState}>
                    <Text style={[styles.emptyStateText, { color: theme.colors.text }]}>
                      No files found
                    </Text>
                    <Text style={[styles.emptyStateSubtext, { color: theme.colors.text + '80' }]}>
                      Vault: {vaultPath}
                    </Text>
                    <TouchableOpacity
                      style={[styles.refreshButtonLarge, { backgroundColor: theme.colors.primary }]}
                      onPress={syncAndRefreshFiles}
                    >
                      <Text style={[styles.refreshButtonLargeText, { color: theme.colors.background }]}>
                        Refresh
                      </Text>
                    </TouchableOpacity>
                  </View>
                }
              />
            )}
          </Animated.View>
        </View>
      </Modal>
    </>
  );
}

const styles = StyleSheet.create({
  hamburgerButton: {
    padding: 12,
    justifyContent: 'center',
    alignItems: 'center',
  },
  hamburgerIcon: {
    width: 24,
    height: 18,
    justifyContent: 'space-between',
  },
  hamburgerLine: {
    height: 2.5,
    borderRadius: 1.5,
    width: '100%',
  },
  modalContainer: {
    flex: 1,
    flexDirection: 'row',
  },
  overlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.4)',
  },
  drawer: {
    width: Dimensions.get('window').width * 0.82,
    height: '100%',
    shadowColor: '#000',
    shadowOffset: { width: 4, height: 0 },
    shadowOpacity: 0.1,
    shadowRadius: 12,
    elevation: 8,
    borderTopRightRadius: 24,
    borderBottomRightRadius: 24,
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 20,
    borderBottomWidth: 1,
  },
  headerTitleContainer: {
    flex: 1,
    marginRight: 12,
  },
  headerTitle: {
    fontSize: 22,
    fontWeight: '800',
    letterSpacing: -0.5,
  },
  headerRepo: {
    fontSize: 13,
    marginTop: 4,
    fontWeight: '500',
  },
  lastUpdatedText: {
    fontSize: 11,
    marginTop: 6,
    fontStyle: 'italic',
  },
  headerButtons: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  refreshButton: {
    padding: 10,
    borderRadius: 8,
    backgroundColor: 'rgba(0,0,0,0.03)',
  },
  refreshButtonText: {
    fontSize: 18,
  },
  viewToggleButton: {
    padding: 10,
    borderRadius: 8,
    backgroundColor: 'rgba(0,0,0,0.03)',
  },
  viewToggleText: {
    fontSize: 18,
  },
  newItemRow: {
    flexDirection: 'row',
    marginHorizontal: 20,
    marginBottom: 20,
    gap: 10,
  },
  newItemButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    padding: 12,
    borderRadius: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  newItemText: {
    fontSize: 15,
    fontWeight: '700',
    letterSpacing: -0.2,
  },
  todayNoteButton: {
    marginHorizontal: 20,
    marginTop: 20,
    marginBottom: 12,
    padding: 14,
    borderRadius: 12,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  todayNoteText: {
    fontSize: 16,
    fontWeight: '700',
    letterSpacing: -0.2,
  },
  sortControlsContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    marginBottom: 12,
    gap: 8,
  },
  sortButtonGroup: {
    flexDirection: 'row',
    borderRadius: 999,
    padding: 4,
    gap: 6,
    borderWidth: 1,
  },
  sortGroupButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 7,
    paddingHorizontal: 12,
    borderRadius: 999,
    minWidth: 86,
    borderWidth: 1,
  },
  sortGroupText: {
    fontSize: 13,
    letterSpacing: -0.1,
  },
  sortDirectionButton: {
    width: 38,
    height: 38,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
  },
  fileList: {
    flex: 1,
  },
  folderItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingRight: 20,
  },
  folderIcon: {
    fontSize: 18,
    marginRight: 10,
  },
  folderName: {
    fontSize: 16,
    fontWeight: '600',
    letterSpacing: -0.2,
  },
  fileItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingRight: 20,
    marginHorizontal: 8,
    borderRadius: 8,
  },
  fileIcon: {
    fontSize: 16,
    marginRight: 10,
  },
  fileName: {
    fontSize: 15,
    fontWeight: '400',
  },
  loadingText: {
    textAlign: 'center',
    padding: 24,
    fontSize: 16,
    fontWeight: '500',
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    marginTop: 48,
  },
  emptyState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    marginTop: 48,
  },
  emptyStateText: {
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 8,
    letterSpacing: -0.5,
  },
  emptyStateSubtext: {
    fontSize: 13,
    marginBottom: 24,
    textAlign: 'center',
    lineHeight: 18,
  },
  refreshButtonLarge: {
    paddingHorizontal: 28,
    paddingVertical: 14,
    borderRadius: 12,
    marginTop: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  refreshButtonLargeText: {
    fontSize: 16,
    fontWeight: '700',
    letterSpacing: -0.2,
  },
  pinnedSection: {
    marginHorizontal: 20,
    marginBottom: 16,
  },
  pinnedHeader: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.8,
    marginBottom: 8,
    marginLeft: 4,
  },
  pinnedList: {
    flexDirection: 'column',
  },
  pinnedItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderRadius: 8,
    marginBottom: 4,
  },
  pinnedIcon: {
    marginRight: 10,
  },
  pinnedName: {
    fontSize: 14,
    fontWeight: '500',
    flex: 1,
  },
  templatesChip: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 4,
    marginLeft: 8,
  },
  templatesChipText: {
    fontSize: 10,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  searchContainer: {
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(0, 0, 0, 0.1)',
  },
  searchInputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: 'rgba(0, 0, 0, 0.05)',
  },
  searchIcon: {
    marginRight: 8,
  },
  searchInput: {
    flex: 1,
    fontSize: 16,
    padding: 0,
  },
  searchSpinner: {
    marginLeft: 8,
  },
  searchButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 8,
    marginTop: 12,
    minHeight: 44,
  },
  searchButtonText: {
    fontSize: 15,
    fontWeight: '700',
    letterSpacing: -0.2,
  },
  searchResultsContainer: {
    marginTop: 12,
    maxHeight: 300,
  },
  searchResultsHeader: {
    fontSize: 12,
    fontWeight: '600',
    marginBottom: 8,
    paddingHorizontal: 4,
  },
  searchResultsList: {
    maxHeight: 250,
  },
  searchResultItem: {
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderBottomWidth: 1,
  },
  searchResultItemActive: {
    backgroundColor: 'rgba(74, 144, 226, 0.1)',
  },
  searchResultHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 4,
  },
  searchResultFileName: {
    fontSize: 14,
    fontWeight: '600',
    marginLeft: 6,
    flex: 1,
  },
  searchResultLineNumber: {
    fontSize: 11,
    marginLeft: 8,
  },
  searchResultPreview: {
    fontSize: 13,
    lineHeight: 18,
    marginLeft: 22,
  },
});
