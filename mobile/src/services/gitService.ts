import git from 'isomorphic-git';
import http from 'isomorphic-git/http/web';
import fs from 'expo-fs';
import AsyncStorage from '@react-native-async-storage/async-storage';

export enum GitErrorType {
  AUTH_FAILURE = 'AUTH_FAILURE',
  NETWORK_ERROR = 'NETWORK_ERROR',
  CONFLICT = 'CONFLICT',
  NOT_A_REPOSITORY = 'NOT_A_REPOSITORY',
  UNKNOWN = 'UNKNOWN',
}

export class GitError extends Error {
  type: GitErrorType;
  originalError?: Error;

  constructor(message: string, type: GitErrorType, originalError?: Error) {
    super(message);
    this.name = 'GitError';
    this.type = type;
    this.originalError = originalError;
  }
}

interface GitCredentials {
  username: string;
  token: string;
}

interface CredentialsMap {
  [repoUrl: string]: GitCredentials;
}

interface StatusResult {
  modified: string[];
  deleted: string[];
  added: string[];
  hasChanges: boolean;
}

interface SyncResult {
  pulled: boolean;
  committed: string | null;
  pushed: boolean;
}

const CREDENTIALS_KEY = 'git_credentials';

function getGitErrorType(error: Error): GitErrorType {
  const message = error.message.toLowerCase();
  
  if (message.includes('401') || message.includes('unauthorized') || message.includes('auth')) {
    return GitErrorType.AUTH_FAILURE;
  }
  if (message.includes('network') || message.includes('fetch') || message.includes('connection')) {
    return GitErrorType.NETWORK_ERROR;
  }
  if (message.includes('conflict') || message.includes('merge')) {
    return GitErrorType.CONFLICT;
  }
  if (message.includes('not a git repository')) {
    return GitErrorType.NOT_A_REPOSITORY;
  }
  
  return GitErrorType.UNKNOWN;
}

export class GitService {
  private static instance: GitService | null = null;
  private fs: typeof fs.promises;

  private constructor() {
    // expo-fs provides a Node.js fs-compatible API
    this.fs = fs.promises;
  }

  static getInstance(): GitService {
    if (!GitService.instance) {
      GitService.instance = new GitService();
    }
    return GitService.instance;
  }

  static clearInstance(): void {
    GitService.instance = null;
  }

  private static async getAuthCallback(url: string): Promise<git.AuthCallback | undefined> {
    const credentials = await GitService.getCredentials(url);
    if (!credentials) {
      return undefined;
    }

    return () => ({
      username: credentials.username,
      password: credentials.token,
    });
  }

  private handleError(error: Error, operation: string): never {
    const errorType = getGitErrorType(error);
    const message = `${operation} failed: ${error.message}`;
    throw new GitError(message, errorType, error);
  }

  // Authentication Methods
  static async setCredentials(repoUrl: string, username: string, token: string): Promise<void> {
    const existingData = await AsyncStorage.getItem(CREDENTIALS_KEY);
    const credentials: CredentialsMap = existingData ? JSON.parse(existingData) : {};
    
    credentials[repoUrl] = { username, token };
    
    await AsyncStorage.setItem(CREDENTIALS_KEY, JSON.stringify(credentials));
  }

  static async getCredentials(repoUrl: string): Promise<GitCredentials | null> {
    const data = await AsyncStorage.getItem(CREDENTIALS_KEY);
    if (!data) {
      return null;
    }

    const credentials: CredentialsMap = JSON.parse(data);
    return credentials[repoUrl] || null;
  }

  static async clearCredentials(): Promise<void> {
    await AsyncStorage.removeItem(CREDENTIALS_KEY);
  }

  // Git Operations
  async clone(
    url: string,
    dir: string,
    onProgress?: git.ProgressCallback
  ): Promise<void> {
    try {
      await git.clone({
        fs: this.fs,
        http,
        dir,
        url,
        onProgress,
        singleBranch: true,
        depth: 1,
        onAuth: await GitService.getAuthCallback(url),
      });
    } catch (error) {
      this.handleError(error as Error, 'Clone');
    }
  }

  async pull(dir: string): Promise<void> {
    try {
      const remoteUrl = await this.getRemoteUrl(dir);
      
      await git.pull({
        fs: this.fs,
        http,
        dir,
        fastForwardOnly: false,
        singleBranch: true,
        onAuth: await GitService.getAuthCallback(remoteUrl),
      });
    } catch (error) {
      this.handleError(error as Error, 'Pull');
    }
  }

  async commit(dir: string): Promise<string | null> {
    try {
      const status = await git.statusMatrix({ fs: this.fs, dir });
      
      let hasChanges = false;
      const modifiedFiles: string[] = [];
      const deletedFiles: string[] = [];
      
      for (const [filepath, headStatus, workdirStatus, stageStatus] of status) {
        // workdirStatus !== stageStatus means there's a change
        if (workdirStatus !== stageStatus) {
          hasChanges = true;
          
          if (workdirStatus === 0) {
            // Deleted
            deletedFiles.push(filepath);
            await git.remove({ fs: this.fs, dir, filepath });
          } else {
            // Modified or added
            modifiedFiles.push(filepath);
            await git.add({ fs: this.fs, dir, filepath });
          }
        }
      }
      
      if (!hasChanges) {
        return null;
      }
      
      const timestamp = new Date().toISOString();
      const message = `Synapse mobile sync — ${timestamp}`;
      
      const sha = await git.commit({
        fs: this.fs,
        dir,
        message,
        author: {
          name: 'Synapse Mobile',
          email: 'mobile@synapse.local',
        },
      });
      
      return sha;
    } catch (error) {
      this.handleError(error as Error, 'Commit');
    }
  }

  async push(dir: string): Promise<void> {
    try {
      const remoteUrl = await this.getRemoteUrl(dir);
      const currentBranch = await git.currentBranch({ fs: this.fs, dir, fullname: false });
      
      await git.push({
        fs: this.fs,
        http,
        dir,
        remote: 'origin',
        ref: currentBranch || 'main',
        onAuth: await GitService.getAuthCallback(remoteUrl),
      });
    } catch (error) {
      this.handleError(error as Error, 'Push');
    }
  }

  async sync(dir: string): Promise<SyncResult> {
    let pulled = false;
    let committed: string | null = null;
    let pushed = false;
    
    try {
      await this.pull(dir);
      pulled = true;
    } catch (error) {
      // Pull failed, but we can still try to commit and push
      console.warn('Pull failed during sync:', error);
    }
    
    committed = await this.commit(dir);
    
    if (committed) {
      try {
        await this.push(dir);
        pushed = true;
      } catch (error) {
        console.warn('Push failed during sync:', error);
      }
    }
    
    return { pulled, committed, pushed };
  }

  // Helper Methods
  async getStatus(dir: string): Promise<StatusResult> {
    try {
      const status = await git.statusMatrix({ fs: this.fs, dir });
      
      const modified: string[] = [];
      const deleted: string[] = [];
      const added: string[] = [];
      
      for (const [filepath, headStatus, workdirStatus, stageStatus] of status) {
        // Check if file has uncommitted changes
        if (workdirStatus !== stageStatus) {
          if (headStatus === 0) {
            // New file (not in HEAD)
            added.push(filepath);
          } else if (workdirStatus === 0) {
            // Deleted file (not in workdir but was in HEAD)
            deleted.push(filepath);
          } else {
            // Modified file (in HEAD but workdir differs from stage)
            modified.push(filepath);
          }
        }
      }
      
      return {
        modified,
        deleted,
        added,
        hasChanges: modified.length > 0 || deleted.length > 0 || added.length > 0,
      };
    } catch (error) {
      this.handleError(error as Error, 'Get status');
    }
  }

  async hasChanges(dir: string): Promise<boolean> {
    const status = await this.getStatus(dir);
    return status.hasChanges;
  }

  async isRepository(dir: string): Promise<boolean> {
    try {
      await git.currentBranch({ fs: this.fs, dir, fullname: false });
      return true;
    } catch {
      return false;
    }
  }

  private async getRemoteUrl(dir: string): Promise<string> {
    try {
      const remote = await git.getConfig({ fs: this.fs, dir, path: 'remote.origin.url' });
      return remote?.value || '';
    } catch {
      return '';
    }
  }

  // Static wrappers for convenience
  static async clone(
    url: string,
    dir: string,
    onProgress?: git.ProgressCallback
  ): Promise<void> {
    return GitService.getInstance().clone(url, dir, onProgress);
  }

  static async pull(dir: string): Promise<void> {
    return GitService.getInstance().pull(dir);
  }

  static async commit(dir: string): Promise<string | null> {
    return GitService.getInstance().commit(dir);
  }

  static async push(dir: string): Promise<void> {
    return GitService.getInstance().push(dir);
  }

  static async sync(dir: string): Promise<SyncResult> {
    return GitService.getInstance().sync(dir);
  }

  static async getStatus(dir: string): Promise<StatusResult> {
    return GitService.getInstance().getStatus(dir);
  }

  static async hasChanges(dir: string): Promise<boolean> {
    return GitService.getInstance().hasChanges(dir);
  }

  static async isRepository(dir: string): Promise<boolean> {
    return GitService.getInstance().isRepository(dir);
  }
}
