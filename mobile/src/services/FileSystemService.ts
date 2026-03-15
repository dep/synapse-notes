import * as FileSystem from 'expo-file-system/legacy';

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

interface FileSystemEntity {
  name: string;
  isDirectory: boolean;
}

// Helper to normalize file:// URIs for Android
const normalizeFileUri = (inputPath: string): string => {
  if (!inputPath) {
    return inputPath;
  }

  // Already has three slashes, return as-is
  if (inputPath.startsWith('file:///')) {
    return inputPath;
  }

  // Android returns 'file:/data/user/...' - convert to 'file:///data/user/...'
  if (inputPath.startsWith('file://')) {
    return `file:///${inputPath.slice('file://'.length).replace(/^\/+/, '')}`;
  }

  if (inputPath.startsWith('file:/')) {
    return `file:///${inputPath.slice('file:/'.length).replace(/^\/+/, '')}`;
  }

  // Absolute path without file:// prefix
  if (inputPath.startsWith('/')) {
    return `file://${inputPath}`;
  }

  // Relative path - prepend document directory
  const docDir = (FileSystem.documentDirectory || 'file:///').replace(/\/+$/, '');
  return `${docDir}/${inputPath.replace(/^\/+/, '')}`;
};

function getFileSystemErrorType(error: Error): FileSystemErrorType {
  const message = error.message.toLowerCase();
  
  if (message.includes('enoent') || message.includes('no such file') || message.includes('could not find')) {
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

  private constructor() {}

  static getInstance(): FileSystemService {
    if (!FileSystemService.instance) {
      FileSystemService.instance = new FileSystemService();
    }
    return FileSystemService.instance;
  }

  static clearInstance(): void {
    FileSystemService.instance = null;
  }

  private sortNodes(files: FileNode[]): FileNode[] {
    return files.sort((a, b) => {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.localeCompare(b.name);
    });
  }

  // List only immediate children in a directory
  async listDirectory(dirPath: string): Promise<FileNode[]> {
    try {
      const normalizedPath = normalizeFileUri(dirPath);
      const entries = await FileSystem.readDirectoryAsync(normalizedPath);
      const files: FileNode[] = [];

      for (const entry of entries) {
        if (entry.startsWith('.') || entry.endsWith('.symlink')) {
          continue;
        }

        const fullPath = FileSystemService.join(normalizedPath, entry);

        let info;
        try {
          info = await FileSystem.getInfoAsync(fullPath);
        } catch (error) {
          console.log(`Skipping ${entry}: ${(error as Error).message}`);
          continue;
        }

        if (!info.exists) {
          continue;
        }

        files.push({
          path: fullPath,
          name: entry,
          isDirectory: info.isDirectory,
          size: info.size || 0,
          modifiedAt: info.modificationTime ? new Date(info.modificationTime * 1000) : new Date(),
        });
      }

      return this.sortNodes(files);
    } catch (error) {
      handleFileSystemError(error as Error, 'List directory');
    }
  }

  // List files recursively in a directory
  async listFiles(dirPath: string): Promise<FileNode[]> {
    try {
      const files = await this.listDirectory(dirPath);

      for (const node of files) {
        if (node.isDirectory) {
          try {
            node.children = await this.listFiles(node.path);
          } catch (error) {
            console.log(`Could not list contents of ${node.name}: ${(error as Error).message}`);
            node.children = [];
          }
        }
      }

      return files;
    } catch (error) {
      handleFileSystemError(error as Error, 'List files');
    }
  }

  // Read file contents
  async readFile(filePath: string, encoding: 'utf8' | 'buffer' = 'utf8'): Promise<string | Uint8Array> {
    try {
      const normalizedPath = normalizeFileUri(filePath);
      const content = await FileSystem.readAsStringAsync(normalizedPath, {
        encoding: FileSystem.EncodingType.UTF8,
      });
      
      if (encoding === 'buffer') {
        return new TextEncoder().encode(content);
      }
      return content;
    } catch (error) {
      handleFileSystemError(error as Error, 'Read file');
    }
  }

  // Write file contents
  async writeFile(filePath: string, content: string | Uint8Array): Promise<void> {
    try {
      const normalizedPath = normalizeFileUri(filePath);
      
      // Ensure parent directory exists
      const dirPath = FileSystemService.dirname(filePath);
      if (dirPath !== '/' && !(await this.exists(dirPath))) {
        await this.createDirectory(dirPath, { recursive: true });
      }

      let contentString: string;
      if (content instanceof Uint8Array) {
        contentString = new TextDecoder().decode(content);
      } else {
        contentString = content;
      }

      await FileSystem.writeAsStringAsync(normalizedPath, contentString, {
        encoding: FileSystem.EncodingType.UTF8,
      });
    } catch (error) {
      handleFileSystemError(error as Error, 'Write file');
    }
  }

  // Delete a file
  async deleteFile(filePath: string): Promise<void> {
    try {
      const normalizedPath = normalizeFileUri(filePath);
      const info = await FileSystem.getInfoAsync(normalizedPath);
      
      if (!info.exists) {
        throw new FileSystemError(
          'File not found',
          FileSystemErrorType.NOT_FOUND
        );
      }
      
      if (info.isDirectory) {
        throw new FileSystemError(
          'Cannot delete directory using deleteFile, use deleteDirectory instead',
          FileSystemErrorType.IS_DIRECTORY
        );
      }
      
      await FileSystem.deleteAsync(normalizedPath, { idempotent: true });
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
      const normalizedPath = normalizeFileUri(dirPath);
      
      await FileSystem.makeDirectoryAsync(normalizedPath, {
        intermediates: options?.recursive ?? false,
      });
    } catch (error) {
      handleFileSystemError(error as Error, 'Create directory');
    }
  }

  // Delete a directory
  async deleteDirectory(dirPath: string, options?: { recursive?: boolean }): Promise<void> {
    try {
      const normalizedPath = normalizeFileUri(dirPath);
      
      await FileSystem.deleteAsync(normalizedPath, { 
        idempotent: true,
      });
    } catch (error) {
      handleFileSystemError(error as Error, 'Delete directory');
    }
  }

  // Check if path exists
  async exists(path: string): Promise<boolean> {
    try {
      const normalizedPath = normalizeFileUri(path);
      const info = await FileSystem.getInfoAsync(normalizedPath);
      return info.exists;
    } catch {
      return false;
    }
  }

  // Check if path is a directory
  async isDirectory(path: string): Promise<boolean> {
    try {
      const normalizedPath = normalizeFileUri(path);
      const info = await FileSystem.getInfoAsync(normalizedPath);
      return info.exists && info.isDirectory;
    } catch (error) {
      handleFileSystemError(error as Error, 'Check is directory');
    }
  }

  // Get structured file tree
  async getFileTree(rootPath: string): Promise<FileNode> {
    try {
      const normalizedPath = normalizeFileUri(rootPath);
      const name = FileSystemService.basename(normalizedPath);
      const entries = await this.listFiles(normalizedPath);
      
      return {
        path: normalizedPath,
        name,
        isDirectory: true,
        children: entries,
      };
    } catch (error) {
      handleFileSystemError(error as Error, 'Get file tree');
    }
  }

  // Get flat file list (all files without hierarchy)
  async getFlatFileList(dirPath: string): Promise<FileNode[]> {
    const files: FileNode[] = [];
    
    const traverse = async (path: string) => {
      const entries = await this.listDirectory(path);
      
      for (const entry of entries) {
        if (entry.isDirectory) {
          await traverse(entry.path);
        } else if (!entry.isDirectory) {
          files.push(entry);
        }
      }
    };
    
    await traverse(dirPath);
    return files;
  }

  // Path utilities
  static join(...paths: string[]): string {
    // Check if first path is a file:// URI
    const firstPath = paths[0];
    if (firstPath?.startsWith('file:///')) {
      // For file:// URIs, just join the remaining parts without adding leading /
      const remainingPaths = paths.slice(1).map(p => p.replace(/^\/+|\/+$/g, '')).filter(Boolean);
      if (remainingPaths.length === 0) {
        return firstPath;
      }
      return firstPath.replace(/\/+$/, '') + '/' + remainingPaths.join('/');
    }
    
    // For regular paths, join with leading /
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

  static async listDirectory(dirPath: string): Promise<FileNode[]> {
    return FileSystemService.getInstance().listDirectory(dirPath);
  }

  static async readFile(filePath: string, encoding?: 'utf8' | 'buffer'): Promise<string | Uint8Array> {
    return FileSystemService.getInstance().readFile(filePath, encoding);
  }

  static async writeFile(filePath: string, content: string | Uint8Array): Promise<void> {
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

  static async getFlatFileList(dirPath: string): Promise<FileNode[]> {
    return FileSystemService.getInstance().getFlatFileList(dirPath);
  }
}
