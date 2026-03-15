import * as FileSystem from 'expo-file-system/legacy';

export interface FileNode {
  path: string;
  name: string;
  isDirectory: boolean;
  children?: FileNode[];
}

// Helper to get document directory path
const getDocumentDirectory = () => {
  return FileSystem.documentDirectory || 'file:///';
};

// Convert our path format to Expo's file:// URI format
const toExpoUri = (path: string): string => {
  const docDir = getDocumentDirectory();
  // Remove leading slash if present to avoid double slashes
  const cleanPath = path.startsWith('/') ? path.substring(1) : path;
  return `${docDir}${cleanPath}`;
};

// Convert Expo's file:// URI back to our path format
const fromExpoUri = (uri: string): string => {
  const docDir = getDocumentDirectory();
  if (uri.startsWith(docDir)) {
    return uri.substring(docDir.length - 1); // Keep the leading slash
  }
  return uri;
};

class FileSystemService {
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

  /**
   * List all files recursively in the vault root
   * Returns structured file tree data
   */
  async listFiles(dirPath: string): Promise<FileNode[]> {
    try {
      const uri = toExpoUri(dirPath);
      const entries = await FileSystem.readDirectoryAsync(uri);
      const nodes: FileNode[] = [];

      for (const entry of entries) {
        const entryPath = `${dirPath}/${entry}`.replace(/\/+/g, '/');
        const entryUri = toExpoUri(entryPath);
        
        try {
          const fileInfo = await FileSystem.getInfoAsync(entryUri);
          
          const node: FileNode = {
            path: entryPath,
            name: entry,
            isDirectory: fileInfo.isDirectory,
          };

          if (fileInfo.isDirectory) {
            node.children = await this.listFiles(entryPath);
          }

          nodes.push(node);
        } catch (error) {
          // Skip files we can't access
          console.warn(`Cannot access ${entryPath}:`, error);
        }
      }

      return nodes;
    } catch (error) {
      // Directory doesn't exist yet, return empty array
      if ((error as Error).message?.includes('No such file') || 
          (error as Error).message?.includes('ENOENT') ||
          (error as Error).message?.includes('doesn\'t exist')) {
        return [];
      }
      throw error;
    }
  }

  /**
   * Read file contents by path
   */
  async readFile(filePath: string): Promise<string> {
    const uri = toExpoUri(filePath);
    return await FileSystem.readAsStringAsync(uri, {
      encoding: FileSystem.EncodingType.UTF8,
    });
  }

  /**
   * Write file contents by path (create or overwrite)
   */
  async writeFile(filePath: string, content: string): Promise<void> {
    try {
      const uri = toExpoUri(filePath);
      await FileSystem.writeAsStringAsync(uri, content, {
        encoding: FileSystem.EncodingType.UTF8,
      });
    } catch (error) {
      // If file write fails (e.g., parent directory doesn't exist), create directories
      const lastSlashIndex = filePath.lastIndexOf('/');
      if (lastSlashIndex > 0) {
        const dirPath = filePath.substring(0, lastSlashIndex);
        await this.createDirectory(dirPath);
        
        // Try writing again
        const uri = toExpoUri(filePath);
        await FileSystem.writeAsStringAsync(uri, content, {
          encoding: FileSystem.EncodingType.UTF8,
        });
      } else {
        throw error;
      }
    }
  }

  /**
   * Delete a file by path
   */
  async deleteFile(filePath: string): Promise<void> {
    const uri = toExpoUri(filePath);
    await FileSystem.deleteAsync(uri, { idempotent: true });
  }

  /**
   * Create a directory
   */
  async createDirectory(dirPath: string): Promise<void> {
    const uri = toExpoUri(dirPath);
    await FileSystem.makeDirectoryAsync(uri, { intermediates: true });
  }

  /**
   * Get flat list of all files (sorted alphabetically)
   */
  async getFlatFileList(dirPath: string): Promise<FileNode[]> {
    const tree = await this.listFiles(dirPath);
    const flatList: FileNode[] = [];

    const flatten = (nodes: FileNode[]) => {
      for (const node of nodes) {
        if (node.isDirectory && node.children) {
          flatten(node.children);
        } else {
          flatList.push(node);
        }
      }
    };

    flatten(tree);

    // Sort alphabetically by name
    return flatList.sort((a, b) => a.name.localeCompare(b.name));
  }

  // Static wrappers for convenience
  static async listFiles(dirPath: string): Promise<FileNode[]> {
    return FileSystemService.getInstance().listFiles(dirPath);
  }

  static async readFile(filePath: string): Promise<string> {
    return FileSystemService.getInstance().readFile(filePath);
  }

  static async writeFile(filePath: string, content: string): Promise<void> {
    return FileSystemService.getInstance().writeFile(filePath, content);
  }

  static async deleteFile(filePath: string): Promise<void> {
    return FileSystemService.getInstance().deleteFile(filePath);
  }

  static async createDirectory(dirPath: string): Promise<void> {
    return FileSystemService.getInstance().createDirectory(dirPath);
  }

  static async getFlatFileList(dirPath: string): Promise<FileNode[]> {
    return FileSystemService.getInstance().getFlatFileList(dirPath);
  }
}

export { FileSystemService };
