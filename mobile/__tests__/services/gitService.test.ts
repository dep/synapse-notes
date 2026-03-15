import { GitService, GitError, GitErrorType } from '../../src/services/gitService';
import git from 'isomorphic-git';
import * as FileSystem from 'expo-file-system/legacy';
import AsyncStorage from '@react-native-async-storage/async-storage';

// Mock dependencies
jest.mock('isomorphic-git');
jest.mock('expo-file-system/legacy', () => ({
  documentDirectory: 'file:///mock/documents/',
  EncodingType: { UTF8: 'utf8', Base64: 'base64' },
  readAsStringAsync: jest.fn(),
  writeAsStringAsync: jest.fn(),
  readDirectoryAsync: jest.fn(),
  getInfoAsync: jest.fn(),
  makeDirectoryAsync: jest.fn(),
  deleteAsync: jest.fn(),
  copyAsync: jest.fn(),
}));
jest.mock('@react-native-async-storage/async-storage', () => ({
  setItem: jest.fn(() => Promise.resolve()),
  getItem: jest.fn(() => Promise.resolve(null)),
  removeItem: jest.fn(() => Promise.resolve()),
}));

const mockFetch = jest.fn();
(global as any).fetch = mockFetch;

describe('GitService', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterEach(() => {
    GitService.clearInstance();
  });

  describe('Authentication', () => {
    describe('setCredentials', () => {
      it('should store credentials securely in AsyncStorage', async () => {
        const username = 'testuser';
        const token = 'ghp_testtoken123';
        const repoUrl = 'https://github.com/test/repo.git';

        await GitService.setCredentials(repoUrl, username, token);

        expect(AsyncStorage.setItem).toHaveBeenCalledWith(
          'git_credentials',
          expect.any(String)
        );
        
        const storedData = JSON.parse(
          (AsyncStorage.setItem as jest.Mock).mock.calls[0][1]
        );
        expect(storedData[repoUrl]).toEqual({ username, token });
      });

      it('should handle multiple repositories', async () => {
        // Mock AsyncStorage.getItem to return accumulated credentials
        let storedCredentials: any = {};
        (AsyncStorage.getItem as jest.Mock).mockImplementation(() => {
          return Promise.resolve(Object.keys(storedCredentials).length > 0 
            ? JSON.stringify(storedCredentials) 
            : null);
        });
        (AsyncStorage.setItem as jest.Mock).mockImplementation((key: string, value: string) => {
          storedCredentials = JSON.parse(value);
          return Promise.resolve();
        });

        await GitService.setCredentials('https://github.com/user/repo1.git', 'user1', 'token1');
        await GitService.setCredentials('https://github.com/user/repo2.git', 'user2', 'token2');

        expect(Object.keys(storedCredentials)).toHaveLength(2);
        expect(storedCredentials['https://github.com/user/repo1.git']).toEqual({ username: 'user1', token: 'token1' });
        expect(storedCredentials['https://github.com/user/repo2.git']).toEqual({ username: 'user2', token: 'token2' });
      });
    });

    describe('getCredentials', () => {
      it('should retrieve stored credentials', async () => {
        const credentials = {
          'https://github.com/test/repo.git': { username: 'testuser', token: 'testtoken' },
        };
        (AsyncStorage.getItem as jest.Mock).mockResolvedValueOnce(JSON.stringify(credentials));

        const result = await GitService.getCredentials('https://github.com/test/repo.git');

        expect(result).toEqual({ username: 'testuser', token: 'testtoken' });
      });

      it('should return null when no credentials exist', async () => {
        (AsyncStorage.getItem as jest.Mock).mockResolvedValueOnce(null);

        const result = await GitService.getCredentials('https://github.com/test/repo.git');

        expect(result).toBeNull();
      });
    });

    describe('clearCredentials', () => {
      it('should remove all stored credentials', async () => {
        await GitService.clearCredentials();

        expect(AsyncStorage.removeItem).toHaveBeenCalledWith('git_credentials');
      });
    });
  });

  describe('clone', () => {
    it('should clone GitHub repositories through the GitHub API fallback', async () => {
      const repoUrl = 'https://github.com/test/repo';
      const localPath = 'file:///mock/documents/vault/repo';

      (AsyncStorage.getItem as jest.Mock).mockResolvedValueOnce(
        JSON.stringify({ [repoUrl]: { username: 'token', token: 'ghp_testtoken123' } })
      );

      mockFetch
        .mockResolvedValueOnce({ ok: true, json: async () => ({ default_branch: 'main' }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ commit: { sha: 'commit-sha-1' } }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ tree: { sha: 'tree-sha-1' } }) })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            tree: [
              { path: 'README.md', type: 'blob', mode: '100644', sha: 'blob-sha-1' },
              { path: 'docs/guide.md', type: 'blob', mode: '100644', sha: 'blob-sha-2' },
            ],
          }),
        })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ content: 'IyBIZWxsbwo=', encoding: 'base64' }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ content: 'R3VpZGUK', encoding: 'base64' }) });

      await GitService.clone(repoUrl, localPath);

      expect(git.clone).not.toHaveBeenCalled();
      expect(mockFetch).toHaveBeenCalled();
      expect(FileSystem.writeAsStringAsync).toHaveBeenCalledWith(
        'file:///mock/documents/vault/repo/README.md',
        'IyBIZWxsbwo=',
        { encoding: 'base64' }
      );
      expect(FileSystem.writeAsStringAsync).toHaveBeenCalledWith(
        'file:///mock/documents/vault/repo/.synapse/repo.json',
        expect.stringContaining('"transport":"github-api"'),
        { encoding: 'utf8' }
      );
    });

    it('should clone repository into app-local storage with progress callback', async () => {
      const repoUrl = 'https://gitlab.com/test/repo.git';
      const localPath = '/repos/test-repo';
      const onProgress = jest.fn();

      (git.clone as jest.Mock).mockResolvedValueOnce(undefined);

      await GitService.clone(repoUrl, localPath, onProgress);

      expect(git.clone).toHaveBeenCalledWith({
        fs: expect.any(Object),
        http: expect.any(Object),
        dir: localPath,
        url: repoUrl,
        onProgress: expect.any(Function),
        singleBranch: true,
        noTags: true,
        depth: 1,
        onAuth: undefined,
      });
    });

    it('should use credentials when available', async () => {
      const repoUrl = 'https://gitlab.com/test/repo.git';
      const localPath = '/repos/test-repo';
      const credentials = { username: 'testuser', token: 'testtoken' };
      
      (AsyncStorage.getItem as jest.Mock).mockResolvedValueOnce(
        JSON.stringify({ [repoUrl]: credentials })
      );
      (git.clone as jest.Mock).mockResolvedValueOnce(undefined);

      await GitService.clone(repoUrl, localPath);

      expect(git.clone).toHaveBeenCalledWith(
        expect.objectContaining({
          onAuth: expect.any(Function),
        })
      );
    });

    it('should expose Node-style ENOENT errors from fs adapter', async () => {
      const repoUrl = 'https://gitlab.com/test/repo.git';
      const localPath = 'file:///data/user/0/com.dnnypck.mobile/files/vault';

      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValueOnce({
        exists: false,
        isDirectory: false,
      });

      (git.clone as jest.Mock).mockImplementationOnce(async ({ fs }: any) => {
        await fs.promises.stat('file:/data/user/0/com.dnnypck.mobile/files/vault/.git/config');
      });

      await expect(GitService.clone(repoUrl, localPath)).rejects.toMatchObject({
        originalError: expect.objectContaining({
          code: 'ENOENT',
          path: 'file:/data/user/0/com.dnnypck.mobile/files/vault/.git/config',
        }),
      });
    });

    it('should create parent directories before writing nested git files', async () => {
      const repoUrl = 'https://gitlab.com/test/repo.git';
      const localPath = 'file:///data/user/0/com.dnnypck.mobile/files/vault/agent-sync';

      (git.clone as jest.Mock).mockImplementationOnce(async ({ fs }: any) => {
        await fs.promises.writeFile(
          'file:/data/user/0/com.dnnypck.mobile/files/vault/agent-sync/.git/config',
          '[core]\nrepositoryformatversion = 0\n'
        );
      });

      await GitService.clone(repoUrl, localPath);

      expect(FileSystem.makeDirectoryAsync).toHaveBeenCalledWith(
        'file:///data/user/0/com.dnnypck.mobile/files/vault/agent-sync/.git',
        { intermediates: true }
      );
      expect(FileSystem.writeAsStringAsync).toHaveBeenCalled();
    });

    it('should throw GitError on authentication failure', async () => {
      const repoUrl = 'https://gitlab.com/test/repo.git';
      const localPath = '/repos/test-repo';
      
      const authError = new Error('HTTP Error: 401 Unauthorized');
      (git.clone as jest.Mock)
        .mockRejectedValueOnce(authError)
        .mockRejectedValueOnce(authError);

      await expect(GitService.clone(repoUrl, localPath)).rejects.toThrow(GitError);
      await expect(GitService.clone(repoUrl, localPath)).rejects.toThrow('401 Unauthorized');
    });

    it('should throw GitError on network error', async () => {
      const repoUrl = 'https://gitlab.com/test/repo.git';
      const localPath = '/repos/test-repo';
      
      (git.clone as jest.Mock).mockRejectedValueOnce(new Error('Network error'));

      await expect(GitService.clone(repoUrl, localPath)).rejects.toThrow(GitError);
    });
  });

  describe('pull', () => {
    it('should pull latest changes with rebase strategy', async () => {
      const localPath = '/repos/test-repo';
      
      (git.pull as jest.Mock).mockResolvedValueOnce(undefined);

      await GitService.pull(localPath);

      expect(git.pull).toHaveBeenCalledWith({
        fs: expect.any(Object),
        http: expect.any(Object),
        dir: localPath,
        fastForwardOnly: false,
        singleBranch: true,
        noTags: true,
        onAuth: undefined,
      });
    });

    it('should throw GitError on conflict', async () => {
      const localPath = '/repos/test-repo';
      
      (git.pull as jest.Mock).mockRejectedValueOnce(new Error('Merge conflict'));

      await expect(GitService.pull(localPath)).rejects.toThrow(GitError);
    });

    it('should throw GitError on network error', async () => {
      const localPath = '/repos/test-repo';
      
      (git.pull as jest.Mock).mockRejectedValueOnce(new Error('Network error'));

      await expect(GitService.pull(localPath)).rejects.toThrow(GitError);
    });
  });

  describe('commit', () => {
    it('should stage all changes and commit with auto-generated message', async () => {
      const localPath = '/repos/test-repo';
      const timestamp = new Date().toISOString();
      
      (git.statusMatrix as jest.Mock).mockResolvedValueOnce([
        ['file1.md', 0, 2, 0], // modified
        ['file2.md', 0, 0, 2], // deleted
      ]);
      (git.add as jest.Mock).mockResolvedValueOnce(undefined);
      (git.remove as jest.Mock).mockResolvedValueOnce(undefined);
      (git.commit as jest.Mock).mockResolvedValueOnce('commit-sha-123');

      const result = await GitService.commit(localPath);

      expect(git.add).toHaveBeenCalledWith({
        fs: expect.any(Object),
        dir: localPath,
        filepath: 'file1.md',
      });
      expect(git.remove).toHaveBeenCalledWith({
        fs: expect.any(Object),
        dir: localPath,
        filepath: 'file2.md',
      });
      expect(git.commit).toHaveBeenCalledWith({
        fs: expect.any(Object),
        dir: localPath,
        message: expect.stringMatching(/Synapse mobile sync/),
        author: expect.objectContaining({
          name: 'Synapse Mobile',
          email: 'mobile@synapse.local',
        }),
      });
      expect(result).toBe('commit-sha-123');
    });

    it('should return null when there are no changes to commit', async () => {
      const localPath = '/repos/test-repo';
      
      (git.statusMatrix as jest.Mock).mockResolvedValueOnce([
        ['file1.md', 1, 1, 1], // unchanged
      ]);

      const result = await GitService.commit(localPath);

      expect(git.commit).not.toHaveBeenCalled();
      expect(result).toBeNull();
    });
  });

  describe('push', () => {
    it('should push commits to remote', async () => {
      const localPath = '/repos/test-repo';
      const remoteUrl = 'https://github.com/test/repo.git';
      
      (git.getConfig as jest.Mock).mockResolvedValueOnce({ value: remoteUrl });
      (git.currentBranch as jest.Mock).mockResolvedValueOnce('main');
      
      // Mock credentials for the remote
      (AsyncStorage.getItem as jest.Mock).mockResolvedValueOnce(
        JSON.stringify({ [remoteUrl]: { username: 'testuser', token: 'testtoken' } })
      );
      
      (git.push as jest.Mock).mockResolvedValueOnce(undefined);

      await GitService.push(localPath);

      expect(git.push).toHaveBeenCalledWith(
        expect.objectContaining({
          fs: expect.any(Object),
          http: expect.any(Object),
          dir: localPath,
          remote: 'origin',
          ref: 'main',
          onAuth: expect.any(Function),
        })
      );
    });

    it('should throw GitError on authentication failure', async () => {
      const localPath = '/repos/test-repo';
      
      (git.push as jest.Mock).mockRejectedValueOnce(new Error('HTTP Error: 401 Unauthorized'));

      await expect(GitService.push(localPath)).rejects.toThrow(GitError);
    });
  });

  describe('sync', () => {
    it('should sync GitHub API repositories by creating a commit through the GitHub API', async () => {
      const localPath = 'file:///mock/documents/vault/repo';
      const metadata = {
        version: 1,
        transport: 'github-api',
        repoUrl: 'https://github.com/test/repo',
        owner: 'test',
        repo: 'repo',
        branch: 'main',
        commitSha: 'commit-sha-1',
        treeSha: 'tree-sha-1',
        files: {
          'README.md': { sha: 'old-readme-sha', mode: '100644', type: 'blob' },
        },
      };

      (AsyncStorage.getItem as jest.Mock).mockResolvedValueOnce(
        JSON.stringify({ ['https://github.com/test/repo']: { username: 'token', token: 'ghp_testtoken123' } })
      );

      (FileSystem.getInfoAsync as jest.Mock).mockImplementation(async (path: string) => {
        if (path === 'file:///mock/documents/vault/repo/.synapse/repo.json') return { exists: true, isDirectory: false, size: 0 };
        if (path === 'file:///mock/documents/vault/repo/README.md') return { exists: true, isDirectory: false, size: 0 };
        return { exists: false, isDirectory: false, size: 0 };
      });
      (FileSystem.readDirectoryAsync as jest.Mock).mockImplementation(async (path: string) => {
        if (path === 'file:///mock/documents/vault/repo') return ['README.md', '.synapse'];
        if (path === 'file:///mock/documents/vault/repo/.synapse') return ['repo.json'];
        return [];
      });
      (FileSystem.readAsStringAsync as jest.Mock).mockImplementation(async (path: string, options?: any) => {
        if (path === 'file:///mock/documents/vault/repo/.synapse/repo.json') return JSON.stringify(metadata);
        if (path === 'file:///mock/documents/vault/repo/README.md' && options?.encoding === 'base64') return 'IyBVcGRhdGVkCg==';
        return '';
      });
      (git.hashBlob as jest.Mock).mockResolvedValueOnce({ oid: 'new-readme-sha' });

      mockFetch
        .mockResolvedValueOnce({ ok: true, json: async () => ({ commit: { sha: 'remote-commit-sha' } }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ sha: 'blob-created-sha' }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ sha: 'tree-created-sha' }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ sha: 'commit-created-sha' }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({}) });

      const result = await GitService.sync(localPath);

      expect(git.push).not.toHaveBeenCalled();
      expect(mockFetch).toHaveBeenCalled();
      expect(result).toEqual({ pulled: true, committed: 'commit-created-sha', pushed: true });
      expect(FileSystem.writeAsStringAsync).toHaveBeenCalledWith(
        'file:///mock/documents/vault/repo/.synapse/repo.json',
        expect.stringContaining('commit-created-sha'),
        { encoding: 'utf8' }
      );
    });

    it('should sync only the provided changed paths for GitHub API repositories', async () => {
      const localPath = 'file:///mock/documents/vault/repo';
      const metadata = {
        version: 1,
        transport: 'github-api',
        repoUrl: 'https://github.com/test/repo',
        owner: 'test',
        repo: 'repo',
        branch: 'main',
        commitSha: 'commit-sha-1',
        treeSha: 'tree-sha-1',
        files: {
          'README.md': { sha: 'old-readme-sha', mode: '100644', type: 'blob' },
          'Other.md': { sha: 'other-sha', mode: '100644', type: 'blob' },
        },
      };

      (AsyncStorage.getItem as jest.Mock).mockResolvedValueOnce(
        JSON.stringify({ ['https://github.com/test/repo']: { username: 'token', token: 'ghp_testtoken123' } })
      );
      (FileSystem.getInfoAsync as jest.Mock).mockImplementation(async (path: string) => {
        if (path === 'file:///mock/documents/vault/repo/.synapse/repo.json') return { exists: true, isDirectory: false, size: 0 };
        if (path === 'file:///mock/documents/vault/repo/README.md') return { exists: true, isDirectory: false, size: 0 };
        return { exists: false, isDirectory: false, size: 0 };
      });
      (FileSystem.readAsStringAsync as jest.Mock).mockImplementation(async (path: string, options?: any) => {
        if (path === 'file:///mock/documents/vault/repo/.synapse/repo.json') return JSON.stringify(metadata);
        if (path === 'file:///mock/documents/vault/repo/README.md' && options?.encoding === 'base64') return 'IyBVcGRhdGVkCg==';
        return '';
      });

      mockFetch
        .mockResolvedValueOnce({ ok: true, json: async () => ({ commit: { sha: 'remote-commit-sha' } }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ sha: 'blob-created-sha' }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ sha: 'tree-created-sha' }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ sha: 'commit-created-sha' }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({}) });

      const result = await GitService.sync(localPath, ['README.md']);

      expect(FileSystem.readDirectoryAsync).not.toHaveBeenCalled();
      expect(FileSystem.readAsStringAsync).toHaveBeenCalledWith(
        'file:///mock/documents/vault/repo/README.md',
        { encoding: 'base64' }
      );
      expect(result).toEqual({ pulled: true, committed: 'commit-created-sha', pushed: true });
    });

    it('should pull then push', async () => {
      const localPath = '/repos/test-repo';
      
      (git.pull as jest.Mock).mockResolvedValueOnce(undefined);
      (git.statusMatrix as jest.Mock).mockResolvedValueOnce([
        ['file1.md', 0, 2, 0],
      ]);
      (git.add as jest.Mock).mockResolvedValueOnce(undefined);
      (git.commit as jest.Mock).mockResolvedValueOnce('commit-sha-123');
      (git.getConfig as jest.Mock).mockResolvedValueOnce({ value: 'https://github.com/test/repo.git' });
      (git.push as jest.Mock).mockResolvedValueOnce(undefined);

      const result = await GitService.sync(localPath);

      expect(git.pull).toHaveBeenCalled();
      expect(git.commit).toHaveBeenCalled();
      expect(git.push).toHaveBeenCalled();
      expect(result).toEqual({
        pulled: true,
        committed: 'commit-sha-123',
        pushed: true,
      });
    });

    it('should handle nothing to commit scenario', async () => {
      const localPath = '/repos/test-repo';
      
      (git.pull as jest.Mock).mockResolvedValueOnce(undefined);
      (git.statusMatrix as jest.Mock).mockResolvedValueOnce([
        ['file1.md', 1, 1, 1], // unchanged
      ]);
      (git.getConfig as jest.Mock).mockResolvedValueOnce({ value: 'https://github.com/test/repo.git' });
      (git.push as jest.Mock).mockResolvedValueOnce(undefined);

      const result = await GitService.sync(localPath);

      expect(result).toEqual({
        pulled: true,
        committed: null,
        pushed: false,
      });
    });
  });

  describe('Error Handling', () => {
    describe('GitError', () => {
      it('should create error with specific type', () => {
        const error = new GitError('Auth failed', GitErrorType.AUTH_FAILURE);
        
        expect(error.message).toBe('Auth failed');
        expect(error.type).toBe(GitErrorType.AUTH_FAILURE);
        expect(error).toBeInstanceOf(Error);
      });

      it('should include original error if provided', () => {
        const original = new Error('Original error');
        const error = new GitError('Auth failed', GitErrorType.AUTH_FAILURE, original);
        
        expect(error.originalError).toBe(original);
      });
    });
  });

  describe('Helper Methods', () => {
    describe('getStatus', () => {
      it('should return current repository status', async () => {
        const localPath = '/repos/test-repo';
        
        (git.statusMatrix as jest.Mock).mockResolvedValueOnce([
          ['file1.md', 1, 1, 1], // unchanged
          ['file2.md', 0, 2, 0], // added (new file)
          ['file3.md', 1, 0, 1], // deleted (was tracked, now gone)
          ['file4.md', 1, 2, 1], // modified (tracked, changed)
        ]);

        const result = await GitService.getStatus(localPath);

        expect(result).toEqual({
          modified: ['file4.md'],
          deleted: ['file3.md'],
          added: ['file2.md'],
          hasChanges: true,
        });
      });
    });

    describe('hasChanges', () => {
      it('should return true when there are uncommitted changes', async () => {
        const localPath = '/repos/test-repo';
        
        (git.statusMatrix as jest.Mock).mockResolvedValueOnce([
          ['file1.md', 1, 1, 1],
          ['file2.md', 0, 2, 0],
        ]);

        const result = await GitService.hasChanges(localPath);

        expect(result).toBe(true);
      });

      it('should return false when working directory is clean', async () => {
        const localPath = '/repos/test-repo';
        
        (git.statusMatrix as jest.Mock).mockResolvedValueOnce([
          ['file1.md', 1, 1, 1],
        ]);

        const result = await GitService.hasChanges(localPath);

        expect(result).toBe(false);
      });
    });

    describe('isRepository', () => {
      it('should return true for valid git repository', async () => {
        const localPath = '/repos/test-repo';
        
        (git.currentBranch as jest.Mock).mockResolvedValueOnce('main');

        const result = await GitService.isRepository(localPath);

        expect(result).toBe(true);
      });

      it('should return false for non-git directory', async () => {
        const localPath = '/repos/test-repo';
        
        (git.currentBranch as jest.Mock).mockRejectedValueOnce(new Error('Not a git repository'));

        const result = await GitService.isRepository(localPath);

        expect(result).toBe(false);
      });
    });
  });
});
