import LightningFS from '@isomorphic-git/lightning-fs';

export enum FileSystemErrorType {
  NOT_FOUND = 'NOT_FOUND',
  PERMISSION_DENIED = 'PERMISSION_DENIED',
  IS_DIRECTORY = 'IS_DIRECTORY',
  NOT_DIRECTORY = 'NOT_DIRECTORY',
  DIRECTORY_NOT_EMPTY = 'DIRECTORY_NOT_EMPTY',
  UNKNOWN = 'UNKNOWN',
}

export class FileSystemError extends Error {
  type: FileSystemErrorType;
  originalError?: Error;

  constructor(message: string, type: FileSystemErrorType, originalError?: Error) {
    super(message);
    this.name = 'FileSystemError';
    this.type = type;
    this.originalError = originalError;
  }
}

export interface FileNode {
  path: string;
  name: string;
  isDirectory: boolean;
  size?: number;
  modifiedAt?: Date;
  children?: FileNode[];
}

interface ReadDirItem {
  name: string;
  type: 'file' | 'directory';
}

function getFileSystemErrorType(error: Error): FileSystemErrorType {
  const message = error.message.toLowerCase();
  
  if (message.includes('enoent') || message.includes('no such file')) {
    return FileSystemErrorType.NOT_FOUND;
  }
  if (message.includes('eacces') || message.includes('permission denied')) {
    return FileSystemErrorType.PERMISSION_DENIED;
  }
  if (message.includes('eisdir') || message.includes('is a directory')) {
    return FileSystemErrorType.IS_DIRECTORY;
  }
  if (message.includes('enotdir') || message.includes('not a directory')) {
    return FileSystemErrorType.NOT_DIRECTORY;
  }
  if (message.includes('enotempty') || message.includes('not empty')) {
    return FileSystemErrorType.DIRECTORY_NOT_EMPTY;
  }
  
  return FileSystemErrorType.UNKNOWN;
}

function handleFileSystemError(error: Error, operation: string): never {
  const errorType = getFileSystemErrorType(error);
  const message = `${operation} failed: ${error.message}`;
  throw new FileSystemError(message, errorType, error);
}

export class FileSystemService {
  private static instance: FileSystemService | null = null;
  private fs: LightningFS;
  private pfs: LightningFS['promises'];

  private constructor() {
    this.fs = new LightningFS('fs');
    this.pfs = this.fs.promises;
  }

  static getInstance(): FileSystemService {
    if (!FileSystemService.instance) {
      FileSystemService.instance = new FileSystemService();
    }
    return FileSystemService.instance;
  }

  static clearInstance(): void {
    FileSystemService.instance = null;
  }

  // List files recursively in a directory
  async listFiles(dirPath: string): Promise<FileNode[]> {
    try {
      const entries = await this.pfs.readdir(dirPath) as ReadDirItem[];
      const files: FileNode[] = [];

      for (const entry of entries) {
        const fullPath = FileSystemService.join(dirPath, entry.name);
        const stats = await this.pfs.stat(fullPath);
        
        const node: FileNode = {
          path: fullPath,
          name: entry.name,
          isDirectory: entry.type === 'directory',
          size: stats.size,
          modifiedAt: new Date(stats.mtimeMs),
        };

        if (entry.type === 'directory') {
          node.children = await this.listFiles(fullPath);
        }

        files.push(node);
      }

      return files;
    } catch (error) {
      handleFileSystemError(error as Error, 'List files');
    }
  }

  // Read file contents
  async readFile(filePath: string, encoding: 'utf8' | 'buffer' = 'utf8'): Promise<string | Buffer> {
    try {
      if (encoding === 'buffer') {
        return await this.pfs.readFile(filePath) as Buffer;
      }
      return await this.pfs.readFile(filePath, 'utf8') as string;
    } catch (error) {
      handleFileSystemError(error as Error, 'Read file');
    }
  }

  // Write file contents
  async writeFile(filePath: string, content: string | Buffer): Promise<void> {
    try {
      // Ensure parent directory exists
      const dirPath = FileSystemService.dirname(filePath);
      if (dirPath !== '/' && !(await this.exists(dirPath))) {
        await this.createDirectory(dirPath, { recursive: true });
      }

      if (typeof content === 'string') {
        await this.pfs.writeFile(filePath, content, 'utf8');
      } else {
        await this.pfs.writeFile(filePath, content);
      }
    } catch (error) {
      handleFileSystemError(error as Error, 'Write file');
    }
  }

  // Delete a file
  async deleteFile(filePath: string): Promise<void> {
    try {
      const stats = await this.pfs.stat(filePath);
      if (stats.type === 'directory') {
        throw new FileSystemError(
          'Cannot delete directory using deleteFile, use deleteDirectory instead',
          FileSystemErrorType.IS_DIRECTORY
        );
      }
      await this.pfs.unlink(filePath);
    } catch (error) {
      if (error instanceof FileSystemError) {
        throw error;
      }
      handleFileSystemError(error as Error, 'Delete file');
    }
  }

  // Create a directory
  async createDirectory(dirPath: string, options?: { recursive?: boolean }): Promise<void> {
    try {
      if (options?.recursive) {
        // Create parent directories recursively
        const parts = dirPath.split('/').filter(Boolean);
        let currentPath = '';
        
        for (const part of parts) {
          currentPath = FileSystemService.join(currentPath, part);
          if (!(await this.exists(currentPath))) {
            await this.pfs.mkdir(currentPath);
          }
        }
      } else {
        await this.pfs.mkdir(dirPath);
      }
    } catch (error) {
      handleFileSystemError(error as Error, 'Create directory');
    }
  }

  // Delete a directory
  async deleteDirectory(dirPath: string, options?: { recursive?: boolean }): Promise<void> {
    try {
      const entries = await this.pfs.readdir(dirPath) as ReadDirItem[];
      
      if (entries.length > 0 && !options?.recursive) {
        throw new FileSystemError(
          'Directory is not empty',
          FileSystemErrorType.DIRECTORY_NOT_EMPTY
        );
      }

      if (options?.recursive) {
        // Delete contents recursively
        for (const entry of entries) {
          const fullPath = FileSystemService.join(dirPath, entry.name);
          if (entry.type === 'directory') {
            await this.deleteDirectory(fullPath, { recursive: true });
          } else {
            await this.pfs.unlink(fullPath);
          }
        }
      }

      await this.pfs.rmdir(dirPath);
    } catch (error) {
      if (error instanceof FileSystemError) {
        throw error;
      }
      handleFileSystemError(error as Error, 'Delete directory');
    }
  }

  // Check if path exists
  async exists(path: string): Promise<boolean> {
    try {
      await this.pfs.stat(path);
      return true;
    } catch {
      return false;
    }
  }

  // Check if path is a directory
  async isDirectory(path: string): Promise<boolean> {
    try {
      const stats = await this.pfs.stat(path);
      return stats.type === 'directory';
    } catch (error) {
      handleFileSystemError(error as Error, 'Check is directory');
    }
  }

  // Get structured file tree
  async getFileTree(rootPath: string): Promise<FileNode> {
    try {
      const name = FileSystemService.basename(rootPath);
      const entries = await this.listFiles(rootPath);
      
      return {
        path: rootPath,
        name,
        isDirectory: true,
        children: entries,
      };
    } catch (error) {
      handleFileSystemError(error as Error, 'Get file tree');
    }
  }

  // Path utilities
  static join(...paths: string[]): string {
    const normalized = paths.map(p => p.replace(/^\/+|\/+$/g, '')).filter(Boolean);
    return '/' + normalized.join('/');
  }

  static dirname(path: string): string {
    const normalized = path.replace(/\/$/, '');
    const lastSlash = normalized.lastIndexOf('/');
    if (lastSlash <= 0) {
      return '/';
    }
    return normalized.substring(0, lastSlash) || '/';
  }

  static basename(path: string): string {
    const normalized = path.replace(/\/$/, '');
    const lastSlash = normalized.lastIndexOf('/');
    if (lastSlash === -1) {
      return normalized;
    }
    return normalized.substring(lastSlash + 1);
  }

  // Static wrappers for convenience
  static async listFiles(dirPath: string): Promise<FileNode[]> {
    return FileSystemService.getInstance().listFiles(dirPath);
  }

  static async readFile(filePath: string, encoding?: 'utf8' | 'buffer'): Promise<string | Buffer> {
    return FileSystemService.getInstance().readFile(filePath, encoding);
  }

  static async writeFile(filePath: string, content: string | Buffer): Promise<void> {
    return FileSystemService.getInstance().writeFile(filePath, content);
  }

  static async deleteFile(filePath: string): Promise<void> {
    return FileSystemService.getInstance().deleteFile(filePath);
  }

  static async createDirectory(dirPath: string, options?: { recursive?: boolean }): Promise<void> {
    return FileSystemService.getInstance().createDirectory(dirPath, options);
  }

  static async deleteDirectory(dirPath: string, options?: { recursive?: boolean }): Promise<void> {
    return FileSystemService.getInstance().deleteDirectory(dirPath, options);
  }

  static async exists(path: string): Promise<boolean> {
    return FileSystemService.getInstance().exists(path);
  }

  static async isDirectory(path: string): Promise<boolean> {
    return FileSystemService.getInstance().isDirectory(path);
  }

  static async getFileTree(rootPath: string): Promise<FileNode> {
    return FileSystemService.getInstance().getFileTree(rootPath);
  }
}
