import React from 'react';
import { render, fireEvent, waitFor } from '@testing-library/react-native';
import { ThemeProvider } from '../../src/theme/ThemeContext';
import { EditorScreen } from '../../src/screens/EditorScreen';
import { FileSystemService } from '../../src/services/FileSystemService';
import { GitService } from '../../src/services/gitService';
import { OnboardingStorage } from '../../src/services/onboardingStorage';

jest.mock('../../src/services/FileSystemService', () => ({
  FileSystemService: {
    readFile: jest.fn(),
    writeFile: jest.fn(),
  },
}));

jest.mock('../../src/services/gitService', () => ({
  GitService: {
    sync: jest.fn(),
  },
}));

jest.mock('../../src/services/onboardingStorage', () => ({
  OnboardingStorage: {
    getActiveRepositoryPath: jest.fn(),
  },
}));

describe('EditorScreen', () => {
  const renderScreen = () =>
    render(
      <ThemeProvider>
        <EditorScreen
          route={{ key: 'Editor', name: 'Editor', params: { filePath: 'file:///vault/repo/note.md' } } as any}
          navigation={{ navigate: jest.fn() } as any}
        />
      </ThemeProvider>
    );

  beforeEach(() => {
    jest.clearAllMocks();
    (FileSystemService.readFile as jest.Mock).mockResolvedValue('# Old note');
    (FileSystemService.writeFile as jest.Mock).mockResolvedValue(undefined);
    (GitService.sync as jest.Mock).mockResolvedValue({ pulled: true, committed: 'sha', pushed: true });
    (OnboardingStorage.getActiveRepositoryPath as jest.Mock).mockResolvedValue('file:///vault/repo');
  });

  it('syncs the active repository after saving a file', async () => {
    const screen = renderScreen();

    await waitFor(() => {
      expect(FileSystemService.readFile).toHaveBeenCalledWith('file:///vault/repo/note.md');
    });

    fireEvent.changeText(screen.getByPlaceholderText('Start typing...'), '# Updated note');
    fireEvent.press(screen.getByText('Save'));

    await waitFor(() => {
      expect(FileSystemService.writeFile).toHaveBeenCalledWith('file:///vault/repo/note.md', '# Updated note');
      expect(GitService.sync).toHaveBeenCalledWith('file:///vault/repo', ['note.md']);
    });
  });
});
