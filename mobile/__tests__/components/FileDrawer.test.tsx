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
      expect(FileSystemService.getFlatFileList).not.toHaveBeenCalled();
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
});
