import fs from 'expo-fs';

export interface FileNode {
  path: string;
  name: string;
  isDirectory: boolean;
  children?: FileNode[];
}

export class FileSystemService {
  private static instance: FileSystemService | null = null;
  private pfs: typeof fs.promises;

  private constructor() {
    this.pfs = fs.promises;
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

  /**
   * List all files recursively in the vault root
   * Returns structured file tree data
   */
  async listFiles(dirPath: string): Promise<FileNode[]> {
    try {
      const entries = await this.pfs.readdir(dirPath);
      const nodes: FileNode[] = [];

      for (const entry of entries) {
        const entryPath = `${dirPath}/${entry}`.replace(/\/+/g, '/');
        const stat = await this.pfs.stat(entryPath);
        const isDirectory = stat.isDirectory();

        const node: FileNode = {
          path: entryPath,
          name: entry,
          isDirectory,
        };

        if (isDirectory) {
          node.children = await this.listFiles(entryPath);
        }

        nodes.push(node);
      }

      return nodes;
    } catch (error) {
      // Directory doesn't exist yet, return empty array
      if ((error as Error).message?.includes('No such file') || 
          (error as Error).message?.includes('ENOENT')) {
        return [];
      }
      throw error;
    }
  }

  /**
   * Read file contents by path
   */
  async readFile(filePath: string): Promise<string> {
    return await this.pfs.readFile(filePath, { encoding: 'utf8' });
  }

  /**
   * Write file contents by path (create or overwrite)
   */
  async writeFile(filePath: string, content: string): Promise<void> {
    try {
      await this.pfs.writeFile(filePath, content, { encoding: 'utf8' });
    } catch (error) {
      // If file write fails (e.g., parent directory doesn't exist), create directories
      const lastSlashIndex = filePath.lastIndexOf('/');
      if (lastSlashIndex > 0) {
        const dirPath = filePath.substring(0, lastSlashIndex);
        await this.pfs.mkdir(dirPath, { recursive: true });
        await this.pfs.writeFile(filePath, content, { encoding: 'utf8' });
      } else {
        throw error;
      }
    }
  }

  /**
   * Delete a file by path
   */
  async deleteFile(filePath: string): Promise<void> {
    await this.pfs.unlink(filePath);
  }

  /**
   * Create a directory
   */
  async createDirectory(dirPath: string): Promise<void> {
    await this.pfs.mkdir(dirPath, { recursive: true });
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
