import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Modal,
  Animated,
  Dimensions,
  ScrollView,
  StatusBar,
  ActivityIndicator,
} from 'react-native';
import { MaterialIcons } from '@expo/vector-icons';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useTheme } from '../theme/ThemeContext';
import { FileSystemService, FileNode } from '../services/FileSystemService';

interface FileDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  onFileSelect: (path: string) => void;
  onNewNote: () => void;
  vaultPath: string;
  repoName?: string;
  activeFilePath?: string;
}

type ViewMode = 'tree' | 'flat';
type SortOption = 'name-asc' | 'name-desc' | 'modified-asc' | 'modified-desc';

const STORAGE_KEYS = {
  viewMode: '@filedrawer_viewmode',
  sortOption: '@filedrawer_sortoption',
};

export function FileDrawer({
  isOpen: initialIsOpen,
  onClose,
  onFileSelect,
  onNewNote,
  vaultPath,
  repoName,
  activeFilePath,
}: FileDrawerProps) {
  const { theme } = useTheme();
  const [isOpen, setIsOpen] = useState(initialIsOpen);
  const [viewMode, setViewMode] = useState<ViewMode>('tree');
  const [sortOption, setSortOption] = useState<SortOption>('name-asc');
  const [files, setFiles] = useState<FileNode[]>([]);
  const [flatFiles, setFlatFiles] = useState<FileNode[]>([]);
  const [expandedFolders, setExpandedFolders] = useState<Set<string>>(new Set());
  const [isLoading, setIsLoading] = useState(false);
  const [isLoadingFlat, setIsLoadingFlat] = useState(false);
  const [loadingFolder, setLoadingFolder] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [lastLoadedVaultPath, setLastLoadedVaultPath] = useState<string | null>(null);
  const slideAnim = useState(new Animated.Value(-Dimensions.get('window').width * 0.8))[0];

  // Load saved preferences on mount
  useEffect(() => {
    const loadPreferences = async () => {
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
      }
    };
    
    loadPreferences();
  }, []);

  // Save view mode when it changes
  useEffect(() => {
    AsyncStorage.setItem(STORAGE_KEYS.viewMode, viewMode).catch(error => {
      console.error('[FileDrawer] Failed to save view mode:', error);
    });
  }, [viewMode]);

  // Save sort option when it changes
  useEffect(() => {
    AsyncStorage.setItem(STORAGE_KEYS.sortOption, sortOption).catch(error => {
      console.error('[FileDrawer] Failed to save sort option:', error);
    });
  }, [sortOption]);

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
  }, [vaultPath]);

  // Animate drawer and load files when opened
  useEffect(() => {
    if (isOpen) {
      Animated.timing(slideAnim, {
        toValue: 0,
        duration: 250,
        useNativeDriver: true,
      }).start();
      // Always load if we haven't loaded for current vaultPath
      const needsLoad = lastLoadedVaultPath !== vaultPath;
      loadRootFiles(needsLoad);
    } else {
      Animated.timing(slideAnim, {
        toValue: -Dimensions.get('window').width * 0.8,
        duration: 250,
        useNativeDriver: true,
      }).start();
    }
  }, [isOpen, vaultPath]);

  useEffect(() => {
    if (isOpen && viewMode === 'flat' && flatFiles.length === 0 && !isLoadingFlat) {
      loadFlatFiles();
    }
  }, [isOpen, viewMode, vaultPath, flatFiles.length, isLoadingFlat, loadFlatFiles]);

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
      const treeFiles = await FileSystemService.listDirectory(vaultPath);
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
  }, [vaultPath, lastLoadedVaultPath]);

  const loadFlatFiles = useCallback(async (forceRefresh = false) => {
    if (!forceRefresh && flatFiles.length > 0) {
      return;
    }

    setIsLoadingFlat(true);
    try {
      const flatFileList = await FileSystemService.getFlatFileList(vaultPath);
      setFlatFiles(flatFileList);
    } catch (error) {
      console.error('[FileDrawer] Failed to load flat files:', error);
    } finally {
      setIsLoadingFlat(false);
    }
  }, [vaultPath, flatFiles.length]);

  const sortFiles = useCallback((nodes: FileNode[]): FileNode[] => {
    const sorted = [...nodes].sort((a, b) => {
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

  const getSortedFiles = useCallback(() => sortFiles(files), [files, sortFiles]);
  const getSortedFlatFiles = useCallback(() => sortFiles(flatFiles), [flatFiles, sortFiles]);

  const openDrawer = () => {
    setIsOpen(true);
  };

  const closeDrawer = () => {
    setIsOpen(false);
    onClose();
  };

  const handleFileSelect = (path: string) => {
    onFileSelect(path);
    closeDrawer();
  };

  const handleNewNote = () => {
    setFiles([]);
    setFlatFiles([]);
    setExpandedFolders(new Set());
    setLastUpdated(null);
    setLastLoadedVaultPath(null);
    onNewNote();
  };

  const toggleFolder = async (path: string, hasLoadedChildren: boolean) => {
    const isExpanding = !expandedFolders.has(path);
    
    if (isExpanding && !hasLoadedChildren) {
      setLoadingFolder(path);
      try {
        const children = await FileSystemService.listDirectory(path);
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
  };

  const toggleViewMode = () => {
    const next = viewMode === 'tree' ? 'flat' : 'tree';
    if (next === 'flat' && flatFiles.length === 0) {
      loadFlatFiles();
    }
    setViewMode(next);
  };

  const renderFileItem = (node: FileNode, level: number = 0) => {
    const isActive = node.path === activeFilePath;
    const isExpanded = expandedFolders.has(node.path);

    if (node.isDirectory) {
      const isLoadingFolder = loadingFolder === node.path;
      
      return (
        <View key={node.path}>
          <TouchableOpacity
            style={[
              styles.folderItem,
              { paddingLeft: 16 + level * 16 },
            ]}
            onPress={() => toggleFolder(node.path, Array.isArray(node.children))}
            disabled={isLoadingFolder}
          >
            {isLoadingFolder ? (
              <ActivityIndicator 
                size="small" 
                color={theme.colors.text} 
                style={styles.folderIcon} 
              />
            ) : (
              <MaterialIcons
                name={isExpanded ? 'folder-open' : 'folder'}
                size={22}
                color={theme.colors.text}
                style={styles.folderIcon}
              />
            )}
            <Text
              style={[
                styles.folderName, 
                { color: theme.colors.text },
                isLoadingFolder && { opacity: 0.7 }
              ]}
              numberOfLines={1}
            >
              {node.name}
            </Text>
          </TouchableOpacity>
          {isExpanded && node.children && (
            <View>
              {node.children.map(child => renderFileItem(child, level + 1))}
            </View>
          )}
        </View>
      );
    }

    return (
      <TouchableOpacity
        key={node.path}
        style={[
          styles.fileItem,
          { paddingLeft: 16 + level * 16 },
          isActive && { backgroundColor: theme.colors.primary + '20' },
        ]}
        onPress={() => handleFileSelect(node.path)}
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
    );
  };

  const renderFlatList = () => {
    return flatFiles.map(node => (
      <TouchableOpacity
        key={node.path}
        style={[
          styles.fileItem,
          node.path === activeFilePath && { backgroundColor: theme.colors.primary + '20' },
        ]}
        onPress={() => handleFileSelect(node.path)}
        testID={node.path === activeFilePath ? 'file-item-active' : undefined}
      >
        <MaterialIcons
          name="insert-drive-file"
          size={20}
          color={node.path === activeFilePath ? theme.colors.primary : theme.colors.text}
          style={styles.fileIcon}
        />
        <Text
          style={[
            styles.fileName,
            { color: theme.colors.text },
            node.path === activeFilePath && { color: theme.colors.primary, fontWeight: '600' },
          ]}
          numberOfLines={1}
        >
          {node.name}
        </Text>
      </TouchableOpacity>
    ));
  };

  return (
    <>
      {/* Hamburger Button */}
      <TouchableOpacity
        style={styles.hamburgerButton}
        onPress={openDrawer}
        testID="hamburger-button"
      >
        <MaterialIcons name="menu" size={28} color={theme.colors.text} />
      </TouchableOpacity>

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
                  onPress={() => loadRootFiles(true)}
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
              style={[styles.newNoteButton, { backgroundColor: theme.colors.primary, flexDirection: 'row', justifyContent: 'center' }]}
              onPress={handleNewNote}
              testID="new-note-button"
            >
              <MaterialIcons name="add" size={20} color={theme.colors.background} style={{ marginRight: 8 }} />
              <Text style={[styles.newNoteText, { color: theme.colors.background }]}>
                New Note
              </Text>
            </TouchableOpacity>

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
            <ScrollView style={styles.fileList}>
              {isLoading ? (
                <View style={styles.loadingContainer}>
                  <ActivityIndicator size="large" color={theme.colors.primary} />
                  <Text style={[styles.loadingText, { color: theme.colors.text, marginTop: 12 }]}>
                    Loading files...
                  </Text>
                </View>
              ) : isLoadingFlat ? (
                <View style={styles.loadingContainer}>
                  <ActivityIndicator size="large" color={theme.colors.primary} />
                  <Text style={[styles.loadingText, { color: theme.colors.text, marginTop: 12 }]}>
                    Loading all files...
                  </Text>
                </View>
              ) : files.length === 0 ? (
                <View style={styles.emptyState}>
                  <Text style={[styles.emptyStateText, { color: theme.colors.text }]}>
                    No files found
                  </Text>
                  <Text style={[styles.emptyStateSubtext, { color: theme.colors.text + '80' }]}>
                    Vault: {vaultPath}
                  </Text>
                  <TouchableOpacity
                    style={[styles.refreshButtonLarge, { backgroundColor: theme.colors.primary }]}
                    onPress={() => loadRootFiles(true)}
                  >
                    <Text style={[styles.refreshButtonLargeText, { color: theme.colors.background }]}>
                      Refresh
                    </Text>
                  </TouchableOpacity>
                </View>
              ) : viewMode === 'tree' ? (
                getSortedFiles().map(node => renderFileItem(node))
              ) : (
                getSortedFlatFiles().map(node => renderFileItem(node))
              )}
            </ScrollView>
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
    paddingTop: StatusBar.currentHeight || 0,
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
  newNoteButton: {
    margin: 20,
    padding: 14,
    borderRadius: 12,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  newNoteText: {
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
});
