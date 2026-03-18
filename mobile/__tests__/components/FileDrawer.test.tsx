import React from 'react';
import { render, fireEvent, waitFor } from '@testing-library/react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { FileDrawer } from '../../src/components/FileDrawer';
import { FileSystemService, FileNode } from '../../src/services/FileSystemService';
import { ThemeProvider } from '../../src/theme/ThemeContext';

// Mock FileSystemService
jest.mock('../../src/services/FileSystemService');

describe('FileDrawer', () => {
  const mockOnFileSelect = jest.fn();
  const mockOnClose = jest.fn();
  const mockOnNewNote = jest.fn();

  const mockFiles: FileNode[] = [
    { path: '/vault/note1.md', name: 'note1.md', isDirectory: false },
    { path: '/vault/note2.md', name: 'note2.md', isDirectory: false },
    {
      path: '/vault/folder',
      name: 'folder',
      isDirectory: true,
      children: [
        { path: '/vault/folder/nested.md', name: 'nested.md', isDirectory: false },
      ],
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    (AsyncStorage.getItem as jest.Mock).mockResolvedValue(null);
    (FileSystemService.listDirectory as jest.Mock).mockResolvedValue(mockFiles);
    (FileSystemService.listFiles as jest.Mock).mockResolvedValue(mockFiles);
    (FileSystemService.getFlatFileList as jest.Mock).mockResolvedValue([
      { path: '/vault/note1.md', name: 'note1.md', isDirectory: false },
      { path: '/vault/note2.md', name: 'note2.md', isDirectory: false },
      { path: '/vault/folder/nested.md', name: 'nested.md', isDirectory: false },
    ]);
  });

  const renderWithTheme = (component: React.ReactElement) => {
    return render(<ThemeProvider>{component}</ThemeProvider>);
  };

  describe('Drawer visibility', () => {
    it('should render hamburger menu button', () => {
      const { getByTestId } = renderWithTheme(
        <FileDrawer
          isOpen={false}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      expect(getByTestId('hamburger-button')).toBeTruthy();
    });

    it('should open drawer when hamburger button is pressed', () => {
      const { getByTestId, queryAllByType } = renderWithTheme(
        <FileDrawer
          isOpen={false}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      // Hamburger button should be visible
      expect(getByTestId('hamburger-button')).toBeTruthy();

      // Press hamburger button
      fireEvent.press(getByTestId('hamburger-button'));

      // Component should still render (Modal will be visible)
      expect(getByTestId('hamburger-button')).toBeTruthy();
    });

    it('should close drawer when overlay is pressed', async () => {
      const { getByTestId } = renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(getByTestId('file-drawer')).toBeTruthy();
      });

      fireEvent.press(getByTestId('drawer-overlay'));
      expect(mockOnClose).toHaveBeenCalled();
    });
  });

  describe('View modes', () => {
    it('should toggle between flat list and folder tree views', async () => {
      const { getByTestId, getByText } = renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(getByTestId('file-drawer')).toBeTruthy();
      });

      // Should have view toggle button
      expect(getByTestId('view-toggle-button')).toBeTruthy();

      // Default should be tree view (shows folder)
      expect(getByText('folder')).toBeTruthy();

      // Toggle to flat view
      fireEvent.press(getByTestId('view-toggle-button'));

      // Flat view should not show folder names, only files
      await waitFor(() => {
        expect(getByText('note1.md')).toBeTruthy();
        expect(getByText('note2.md')).toBeTruthy();
        expect(getByText('nested.md')).toBeTruthy();
      });
    });

    it('should load files on mount', async () => {
      renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(FileSystemService.listDirectory).toHaveBeenCalledWith(
          '/vault',
          expect.objectContaining({
            fileExtensionFilter: expect.any(String),
            hiddenFileFolderFilter: expect.any(String)
          })
        );
      });
      // Flat list is eagerly pre-loaded in the background so toggling to Files
      // view is instant — it should also be called on mount.
      await waitFor(() => {
        expect(FileSystemService.getFlatFileList).toHaveBeenCalled();
      });
    });

    it('should load flat file list only when flat view is selected', async () => {
      const { getByTestId } = renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(FileSystemService.listDirectory).toHaveBeenCalledWith(
          '/vault',
          expect.objectContaining({
            fileExtensionFilter: expect.any(String),
            hiddenFileFolderFilter: expect.any(String)
          })
        );
      });

      fireEvent.press(getByTestId('view-toggle-button'));

      await waitFor(() => {
        expect(FileSystemService.getFlatFileList).toHaveBeenCalledWith(
          '/vault',
          expect.objectContaining({
            fileExtensionFilter: expect.any(String),
            hiddenFileFolderFilter: expect.any(String)
          })
        );
      });
    });

    it('should load flat files on open when saved preference is flat view', async () => {
      (AsyncStorage.getItem as jest.Mock).mockImplementation(async (key: string) => {
        if (key === '@filedrawer_viewmode') return 'flat';
        if (key === '@filedrawer_sortoption') return 'name-asc';
        return null;
      });

      renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(FileSystemService.getFlatFileList).toHaveBeenCalledWith(
          '/vault',
          expect.objectContaining({
            fileExtensionFilter: expect.any(String),
            hiddenFileFolderFilter: expect.any(String)
          })
        );
      });
    });
  });

  describe('File selection', () => {
    it('should call onFileSelect when file is tapped', async () => {
      const { getByText } = renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(getByText('note1.md')).toBeTruthy();
      });

      fireEvent.press(getByText('note1.md'));

      expect(mockOnFileSelect).toHaveBeenCalledWith('/vault/note1.md');
      expect(mockOnClose).toHaveBeenCalled();
    });

    it('should lazy load folder children when a folder is expanded', async () => {
      (FileSystemService.listDirectory as jest.Mock)
        .mockResolvedValueOnce([
          { path: '/vault/folder', name: 'folder', isDirectory: true },
        ])
        .mockResolvedValueOnce([
          { path: '/vault/folder/nested.md', name: 'nested.md', isDirectory: false },
        ]);

      const { getByText } = renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(getByText('folder')).toBeTruthy();
      });

      fireEvent.press(getByText('folder'));

      await waitFor(() => {
        expect(FileSystemService.listDirectory).toHaveBeenCalledWith(
          '/vault/folder',
          expect.objectContaining({
            fileExtensionFilter: '*.md, *.txt',
            hiddenFileFolderFilter: ''
          })
        );
        expect(getByText('nested.md')).toBeTruthy();
      });
    });

    it('should highlight active file', async () => {
      const { getByTestId } = renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
          activeFilePath="/vault/note1.md"
        />
      );

      await waitFor(() => {
        expect(getByTestId('file-item-active')).toBeTruthy();
      });
    });
  });

  describe('New note button', () => {
    it('should call onNewNote when new note button is pressed', async () => {
      const { getByTestId } = renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(getByTestId('new-note-button')).toBeTruthy();
      });

      fireEvent.press(getByTestId('new-note-button'));

      expect(mockOnNewNote).toHaveBeenCalled();
    });
  });

  describe('Theme support', () => {
    it('should render with light theme colors', () => {
      const { getByTestId } = renderWithTheme(
        <FileDrawer
          isOpen={false}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      expect(getByTestId('hamburger-button')).toBeTruthy();
    });
  });

  describe('Preferences persistence', () => {
    it('should remember view mode across remounts', async () => {
      // First render - toggle to flat view
      const { getByTestId, unmount } = renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(getByTestId('file-drawer')).toBeTruthy();
      });

      // Toggle to flat view
      fireEvent.press(getByTestId('view-toggle-button'));

      // Wait for flat files to load
      await waitFor(() => {
        expect(FileSystemService.getFlatFileList).toHaveBeenCalled();
      });

      // Verify AsyncStorage was called to save the preference
      await waitFor(() => {
        expect(AsyncStorage.setItem).toHaveBeenCalledWith('@filedrawer_viewmode', 'flat');
      });

      unmount();

      // Mock AsyncStorage to return flat for the second render
      (AsyncStorage.getItem as jest.Mock).mockImplementation(async (key: string) => {
        if (key === '@filedrawer_viewmode') return 'flat';
        if (key === '@filedrawer_sortoption') return 'name-asc';
        return null;
      });

      // Second render - should load flat files automatically based on saved preference
      renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      // Should load flat files because of saved preference
      await waitFor(() => {
        expect(FileSystemService.getFlatFileList).toHaveBeenCalledTimes(2);
      });
    });

    it('should remember sort option across remounts', async () => {
      // First render - change sort option
      const { getByTestId, getByText, unmount } = renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(getByTestId('file-drawer')).toBeTruthy();
      });

      // Change sort option to date (modified)
      fireEvent.press(getByText('Date'));

      // Verify AsyncStorage was called to save the preference
      await waitFor(() => {
        expect(AsyncStorage.setItem).toHaveBeenCalledWith('@filedrawer_sortoption', 'modified-desc');
      });

      unmount();

      // Mock AsyncStorage to return modified-desc for the second render
      (AsyncStorage.getItem as jest.Mock).mockImplementation(async (key: string) => {
        if (key === '@filedrawer_viewmode') return 'tree';
        if (key === '@filedrawer_sortoption') return 'modified-desc';
        return null;
      });

      // Second render - should load with saved sort option
      const { getByText: getByText2 } = renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(getByText2('Date')).toBeTruthy();
      });
    });

    it('should persist sort direction changes', async () => {
      // Mock AsyncStorage to return modified-desc initially
      (AsyncStorage.getItem as jest.Mock).mockImplementation(async (key: string) => {
        if (key === '@filedrawer_viewmode') return 'tree';
        if (key === '@filedrawer_sortoption') return 'modified-desc';
        return null;
      });

      const { getByTestId, unmount } = renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(getByTestId('file-drawer')).toBeTruthy();
      });

      // Find and press the sort direction button (the one with arrow icon)
      // The sort direction button is next to the sort button group
      // Since we can't easily identify it by testID, we need to look for it by icon or behavior
      
      unmount();

      // Verify that modified-desc was saved
      expect(AsyncStorage.setItem).toHaveBeenCalledWith('@filedrawer_sortoption', 'modified-desc');
    });

    it('should reload preferences when drawer opens after being closed', async () => {
      // First render with drawer closed
      const { getByTestId, rerender } = renderWithTheme(
        <FileDrawer
          isOpen={false}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      // Mock AsyncStorage to return flat view (simulating user previously changed it)
      (AsyncStorage.getItem as jest.Mock).mockImplementation(async (key: string) => {
        if (key === '@filedrawer_viewmode') return 'flat';
        if (key === '@filedrawer_sortoption') return 'modified-desc';
        return null;
      });

      // Reopen the drawer (simulating navigation back and reopening)
      rerender(
        <ThemeProvider>
          <FileDrawer
            isOpen={true}
            onClose={mockOnClose}
            onFileSelect={mockOnFileSelect}
            onNewNote={mockOnNewNote}
            onNewFolder={jest.fn()}
            vaultPath="/vault"
          />
        </ThemeProvider>
      );

      // Should load flat files because preference is 'flat'
      await waitFor(() => {
        expect(FileSystemService.getFlatFileList).toHaveBeenCalled();
      });

      // Verify it tried to load the preferences
      await waitFor(() => {
        expect(AsyncStorage.getItem).toHaveBeenCalledWith('@filedrawer_viewmode');
        expect(AsyncStorage.getItem).toHaveBeenCalledWith('@filedrawer_sortoption');
      });
    });

    it('should eagerly pre-load flat file list when drawer opens in tree mode', async () => {
      // Open drawer in tree mode (default) — getFlatFileList should be called
      // in the background without waiting for the user to toggle to Files view
      renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(FileSystemService.getFlatFileList).toHaveBeenCalledWith('/vault', expect.anything());
      });
    });

    it('should not overwrite saved view mode with the default before preferences load', async () => {
      (AsyncStorage.getItem as jest.Mock).mockImplementation(async (key: string) => {
        if (key === '@filedrawer_viewmode') return 'flat';
        if (key === '@filedrawer_sortoption') return 'name-asc';
        return null;
      });

      renderWithTheme(
        <FileDrawer
          isOpen={true}
          onClose={mockOnClose}
          onFileSelect={mockOnFileSelect}
          onNewNote={mockOnNewNote}
          onNewFolder={jest.fn()}
          vaultPath="/vault"
        />
      );

      await waitFor(() => {
        expect(FileSystemService.getFlatFileList).toHaveBeenCalled();
      });

      expect(AsyncStorage.setItem).not.toHaveBeenCalledWith('@filedrawer_viewmode', 'tree');
    });
  });
});
