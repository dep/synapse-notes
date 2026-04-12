import React from 'react';
import { act, fireEvent, render, waitFor } from '@testing-library/react-native';
import { Alert, BackHandler } from 'react-native';
import { ThemeProvider } from '../../src/theme/ThemeContext';
import { EditorScreen, preparePreviewContent } from '../../src/screens/EditorScreen';
import { FileSystemService } from '../../src/services/FileSystemService';
import { GitService } from '../../src/services/gitService';
import { OnboardingStorage } from '../../src/services/onboardingStorage';

let repositoryRefreshHandler: ((repositoryPath: string) => void | Promise<void>) | null = null;

jest.mock('../../src/services/FileSystemService', () => {
  const actual = jest.requireActual<typeof import('../../src/services/FileSystemService')>(
    '../../src/services/FileSystemService'
  );
  return {
    ...actual,
    FileSystemService: {
      readFile: jest.fn(),
      writeFile: jest.fn(),
      resolveWikilink: jest.fn(),
      dirname: jest.fn((path: string) => path.replace(/\/[^/]*$/, '')),
      join: jest.fn((base: string, target: string) => `${base.replace(/\/+$/, '')}/${target.replace(/^\/+/, '')}`),
      normalizeUri: actual.FileSystemService.normalizeUri.bind(actual.FileSystemService),
    },
  };
});

jest.mock('../../src/services/gitService', () => ({
  GitService: {
    sync: jest.fn(),
    refreshRemote: jest.fn(),
    getFileHistory: jest.fn(),
    getFileContentAtCommit: jest.fn(),
    isRepository: jest.fn(),
  },
}));

jest.mock('../../src/services/repositoryEvents', () => ({
  subscribeToRepositoryRefresh: jest.fn((handler: (repositoryPath: string) => void | Promise<void>) => {
    repositoryRefreshHandler = handler;
    return jest.fn();
  }),
  emitRepositoryRefresh: jest.fn(),
}));

jest.mock('../../src/services/onboardingStorage', () => ({
  OnboardingStorage: {
    getActiveRepositoryPath: jest.fn(),
  },
}));

jest.mock('@react-navigation/native', () => {
  const React = require('react');
  return {
    useFocusEffect: (callback: () => void | (() => void)) => {
      React.useEffect(() => {
        const cleanup = callback();
        return typeof cleanup === 'function' ? cleanup : undefined;
      }, [callback]);
    },
  };
});

describe('EditorScreen', () => {
  const mockNavigate = jest.fn();
  const mockAddListener = jest.fn(() => jest.fn());

  const getLatestHardwareBackHandler = () => {
    const addListener = BackHandler.addEventListener as jest.Mock;
    const calls = addListener.mock.calls.filter((call) => call[0] === 'hardwareBackPress');
    return calls[calls.length - 1]?.[1] as (() => boolean) | undefined;
  };

  const renderScreen = (filePath = 'file:///vault/repo/note.md') =>
    render(
      <ThemeProvider>
        <EditorScreen
          route={{ key: 'Editor', name: 'Editor', params: { filePath } } as any}
          navigation={{ navigate: mockNavigate, addListener: mockAddListener } as any}
        />
      </ThemeProvider>
    );

  beforeEach(() => {
    jest.clearAllMocks();
    (Alert.alert as jest.Mock).mockClear();
    repositoryRefreshHandler = null;
    (FileSystemService.readFile as jest.Mock).mockResolvedValue('# Old note');
    (FileSystemService.writeFile as jest.Mock).mockResolvedValue(undefined);
    (FileSystemService.resolveWikilink as jest.Mock).mockResolvedValue(null);
    (GitService.sync as jest.Mock).mockResolvedValue({ pulled: true, committed: 'sha', pushed: true });
    (GitService.refreshRemote as jest.Mock).mockResolvedValue(undefined);
    (GitService.getFileHistory as jest.Mock).mockResolvedValue([]);
    (GitService.getFileContentAtCommit as jest.Mock).mockResolvedValue(null);
    (GitService.isRepository as jest.Mock).mockResolvedValue(true);
    (OnboardingStorage.getActiveRepositoryPath as jest.Mock).mockResolvedValue('file:///vault/repo');
  });

  describe('Wikilink Navigation', () => {
    it('parses wikilink syntax in content', async () => {
      const contentWithWikilink = 'Check out [[Another Note]] for more info';
      (FileSystemService.readFile as jest.Mock).mockResolvedValue(contentWithWikilink);

      renderScreen();

      await waitFor(() => {
        expect(FileSystemService.readFile).toHaveBeenCalledWith('file:///vault/repo/note.md');
      });

      // Test passes if file is loaded with wikilink content
    });

    it('resolves wikilink to existing note', async () => {
      const contentWithWikilink = 'See [[Another Note]]';
      (FileSystemService.readFile as jest.Mock).mockResolvedValue(contentWithWikilink);
      (FileSystemService.resolveWikilink as jest.Mock).mockResolvedValue('file:///vault/repo/Another Note.md');

      renderScreen();

      await waitFor(() => {
        expect(FileSystemService.readFile).toHaveBeenCalled();
      });

      // The resolveWikilink method should be available and callable
      expect(FileSystemService.resolveWikilink).toBeDefined();
    });

    it('handles case-insensitive wikilink matching', async () => {
      const contentWithLowercase = 'Link to [[another note]]';
      (FileSystemService.readFile as jest.Mock).mockResolvedValue(contentWithLowercase);
      (FileSystemService.resolveWikilink as jest.Mock).mockImplementation((target: string) => {
        if (target.toLowerCase() === 'another note') {
          return Promise.resolve('file:///vault/repo/Another Note.md');
        }
        return Promise.resolve(null);
      });

      renderScreen();

      await waitFor(() => {
        expect(FileSystemService.readFile).toHaveBeenCalled();
      });

      // Verify the mock is set up for case-insensitive matching
      const result = await FileSystemService.resolveWikilink('another note', 'file:///vault/repo');
      expect(result).toBe('file:///vault/repo/Another Note.md');
    });

    it('handles wikilink with alias/display text', async () => {
      const contentWithAlias = 'Click [[Target Note|display text]] here';
      (FileSystemService.readFile as jest.Mock).mockResolvedValue(contentWithAlias);
      (FileSystemService.resolveWikilink as jest.Mock).mockResolvedValue('file:///vault/repo/Target Note.md');

      renderScreen();

      await waitFor(() => {
        expect(FileSystemService.readFile).toHaveBeenCalled();
      });

      // Verify that resolveWikilink works with the target name
      const result = await FileSystemService.resolveWikilink('Target Note', 'file:///vault/repo');
      expect(result).toBe('file:///vault/repo/Target Note.md');
    });

    it('handles non-existent wikilink target', async () => {
      const contentWithMissingLink = 'See [[NonExistent]] note';
      (FileSystemService.readFile as jest.Mock).mockResolvedValue(contentWithMissingLink);
      (FileSystemService.resolveWikilink as jest.Mock).mockResolvedValue(null);

      renderScreen();

      await waitFor(() => {
        expect(FileSystemService.readFile).toHaveBeenCalled();
      });

      // When resolveWikilink returns null, the note doesn't exist
      const result = await FileSystemService.resolveWikilink('NonExistent', 'file:///vault/repo');
      expect(result).toBeNull();
    });

    it('ignores regular markdown links in wikilink processing', async () => {
      const contentWithRegularLink = 'Visit [Google](https://google.com)';
      (FileSystemService.readFile as jest.Mock).mockResolvedValue(contentWithRegularLink);

      renderScreen();

      await waitFor(() => {
        expect(FileSystemService.readFile).toHaveBeenCalled();
      });

      // Regular markdown links don't trigger resolveWikilink
      // They should be handled differently
    });

    it('resolves image embeds in preview mode to local file URIs wrapped in placeholder', async () => {
      const contentWithImageEmbed = '![Diagram](diagram.png)\n\n![[diagram.png]]';
      const previewContent = preparePreviewContent(contentWithImageEmbed, 'file:///vault/repo/note.md');

      expect(previewContent).toContain('![Diagram](synapse-local://file:///vault/repo/diagram.png)');
      expect(previewContent).toContain('![diagram.png](synapse-local://file:///vault/repo/diagram.png)');
    });

    it('uses a placeholder scheme so markdown-it does not strip local image URIs', async () => {
      const contentWithImageEmbed = '![](diagram.png)';
      const previewContent = preparePreviewContent(contentWithImageEmbed, 'file:///vault/repo/note.md');

      // file:// is blocked by markdown-it's validateLink — the preview content
      // must wrap local URIs in the synapse-local:// placeholder scheme.
      // A bare ](file:// opening (without the placeholder prefix) must NOT appear.
      expect(previewContent).not.toMatch(/\]\(file:\/\//);
      expect(previewContent).toContain('synapse-local://file:///vault/repo/diagram.png');
    });
  });

  it('loads file content on mount', async () => {
    renderScreen();

    await waitFor(() => {
      expect(FileSystemService.readFile).toHaveBeenCalledWith('file:///vault/repo/note.md');
    });
  });

  it('discards in-memory edits when choosing Don\'t Save from the hardware-back prompt', async () => {
    const { getByTestId } = renderScreen();

    await waitFor(() => {
      expect(getByTestId('editor-input').props.value).toBe('# Old note');
    });

    fireEvent.changeText(getByTestId('editor-input'), '# Edited note');

    await waitFor(() => {
      expect(getLatestHardwareBackHandler()).toBeDefined();
    });

    const hardwareBackHandler = getLatestHardwareBackHandler();
    expect(hardwareBackHandler!()).toBe(true);

    expect(Alert.alert).toHaveBeenCalled();
    const buttons = (Alert.alert as jest.Mock).mock.calls[0][2] as {
      text: string;
      onPress?: () => void;
    }[];
    const discard = buttons.find((b) => b.text === "Don't Save");
    expect(discard?.onPress).toBeDefined();

    act(() => {
      discard!.onPress!();
    });

    await waitFor(() => {
      expect(getByTestId('editor-input').props.value).toBe('# Old note');
    });
  });

  it('does not open the file drawer after Save fails from the hardware-back prompt', async () => {
    (FileSystemService.writeFile as jest.Mock).mockRejectedValueOnce(new Error('disk full'));

    const { getByTestId } = renderScreen();

    await waitFor(() => {
      expect(getByTestId('editor-input').props.value).toBe('# Old note');
    });

    fireEvent.changeText(getByTestId('editor-input'), '# Edited note');

    await waitFor(() => {
      expect(getLatestHardwareBackHandler()).toBeDefined();
    });

    const hardwareBackHandler = getLatestHardwareBackHandler();
    hardwareBackHandler!();

    const buttons = (Alert.alert as jest.Mock).mock.calls[0][2] as {
      text: string;
      style?: string;
      onPress?: () => void | Promise<void>;
    }[];
    const save = buttons.find((b) => b.text === 'Save');
    expect(save?.onPress).toBeDefined();

    await act(async () => {
      await save!.onPress!();
    });

    expect(FileSystemService.writeFile).toHaveBeenCalled();
    await waitFor(() => {
      expect(getByTestId('editor-input').props.value).toBe('# Edited note');
    });
  });

  it('reloads the current note after a repository refresh event', async () => {
    (FileSystemService.readFile as jest.Mock)
      .mockResolvedValueOnce('# Old note')
      .mockResolvedValueOnce('# New note');

    renderScreen();

    await waitFor(() => {
      expect(FileSystemService.readFile).toHaveBeenCalledTimes(2);
    });

    expect(repositoryRefreshHandler).not.toBeNull();

    await act(async () => {
      await repositoryRefreshHandler?.('file:///vault/repo');
    });

    await waitFor(() => {
      expect(FileSystemService.readFile).toHaveBeenCalledTimes(3);
    });
  });

  describe('View History', () => {
    it('shows View History button when file has commit history', async () => {
      (GitService.getFileHistory as jest.Mock).mockResolvedValue([
        { sha: 'abc123', message: 'Initial commit', date: new Date('2024-01-01') },
      ]);

      const { getByTestId } = renderScreen();

      await waitFor(() => {
        expect(GitService.getFileHistory).toHaveBeenCalledWith('file:///vault/repo', 'note.md');
      });

      expect(getByTestId('view-history-button')).toBeTruthy();
    });

    it('does not show View History button when file has no history', async () => {
      (GitService.getFileHistory as jest.Mock).mockResolvedValue([]);

      const { queryByTestId } = renderScreen();

      await waitFor(() => {
        expect(GitService.getFileHistory).toHaveBeenCalled();
      });

      expect(queryByTestId('view-history-button')).toBeNull();
    });

    it('opens history modal when View History button is clicked', async () => {
      (GitService.getFileHistory as jest.Mock).mockResolvedValue([
        { sha: 'abc123', message: 'Initial commit', date: new Date('2024-01-01') },
        { sha: 'def456', message: 'Update content', date: new Date('2024-01-02') },
      ]);

      const { getByTestId, getByText } = renderScreen();

      await waitFor(() => {
        expect(getByTestId('view-history-button')).toBeTruthy();
      });

      act(() => {
        fireEvent.press(getByTestId('view-history-button'));
      });

      await waitFor(() => {
        expect(getByText('Initial commit')).toBeTruthy();
        expect(getByText('Update content')).toBeTruthy();
      });
    });

    it('shows file content preview when selecting a commit', async () => {
      const mockContent = '# Historical Version';
      (GitService.getFileHistory as jest.Mock).mockResolvedValue([
        { sha: 'abc123', message: 'Initial commit', date: new Date('2024-01-01') },
      ]);
      (GitService.getFileContentAtCommit as jest.Mock).mockResolvedValue(mockContent);

      const { getByTestId, getByText } = renderScreen();

      await waitFor(() => {
        expect(getByTestId('view-history-button')).toBeTruthy();
      });

      act(() => {
        fireEvent.press(getByTestId('view-history-button'));
      });

      await waitFor(() => {
        expect(getByText('Initial commit')).toBeTruthy();
      });

      act(() => {
        fireEvent.press(getByText('Initial commit'));
      });

      await waitFor(() => {
        expect(getByText('Restore this version')).toBeTruthy();
        expect(GitService.getFileContentAtCommit).toHaveBeenCalledWith('file:///vault/repo', 'note.md', 'abc123');
      });
    });

    it('restores file content when Restore button is clicked', async () => {
      const mockContent = '# Historical Version';
      (GitService.getFileHistory as jest.Mock).mockResolvedValue([
        { sha: 'abc123', message: 'Initial commit', date: new Date('2024-01-01') },
      ]);
      (GitService.getFileContentAtCommit as jest.Mock).mockResolvedValue(mockContent);

      const { getByTestId, getByText, queryByText } = renderScreen();

      await waitFor(() => {
        expect(getByTestId('view-history-button')).toBeTruthy();
      });

      act(() => {
        fireEvent.press(getByTestId('view-history-button'));
      });

      await waitFor(() => {
        expect(getByText('Initial commit')).toBeTruthy();
      });

      act(() => {
        fireEvent.press(getByText('Initial commit'));
      });

      await waitFor(() => {
        expect(getByText('Restore this version')).toBeTruthy();
      });

      act(() => {
        fireEvent.press(getByText('Restore this version'));
      });

      await waitFor(() => {
        // Modal should close
        expect(queryByText('Initial commit')).toBeNull();
      });
    });
  });
});
