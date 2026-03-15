import { FileSystemService, FileSystemError, FileSystemErrorType, FileNode } from '../../src/services/fileSystemService';
import * as FileSystem from 'expo-file-system/legacy';

// Mock expo-file-system
jest.mock('expo-file-system/legacy', () => ({
  readDirectoryAsync: jest.fn(),
  readAsStringAsync: jest.fn(),
  writeAsStringAsync: jest.fn(),
  deleteAsync: jest.fn(),
  makeDirectoryAsync: jest.fn(),
  getInfoAsync: jest.fn(),
  documentDirectory: 'file:///mock/documents/',
  EncodingType: {
    UTF8: 'utf8',
  },
}));

describe('FileSystemService', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterEach(() => {
    FileSystemService.clearInstance();
  });

  describe('Singleton Pattern', () => {
    it('should return the same instance', () => {
      const instance1 = FileSystemService.getInstance();
      const instance2 = FileSystemService.getInstance();
      
      expect(instance1).toBe(instance2);
    });

    it('should create new instance after clearing', () => {
      const instance1 = FileSystemService.getInstance();
      FileSystemService.clearInstance();
      const instance2 = FileSystemService.getInstance();
      
      expect(instance1).not.toBe(instance2);
    });
  });

  describe('listFiles', () => {
    it('should list all files recursively in a directory', async () => {
      const rootPath = '/vault';
      
      // First call - root directory
      (FileSystem.readDirectoryAsync as jest.Mock)
        .mockResolvedValueOnce(['file1.md', 'folder1']);
      
      // getInfoAsync calls
      (FileSystem.getInfoAsync as jest.Mock)
        .mockResolvedValueOnce({ exists: true, isDirectory: false, size: 100 }) // file1.md
        .mockResolvedValueOnce({ exists: true, isDirectory: true, size: 0 }) // folder1
        .mockResolvedValueOnce({ exists: true, isDirectory: false, size: 200 }); // file2.md inside folder1

      // Second call - folder1 contents
      (FileSystem.readDirectoryAsync as jest.Mock)
        .mockResolvedValueOnce(['file2.md']);

      const result = await FileSystemService.listFiles(rootPath);

      expect(result).toHaveLength(2);
      expect(result[0].name).toBe('folder1');
      expect(result[0].isDirectory).toBe(true);
      expect(result[1].name).toBe('file1.md');
      expect(result[1].isDirectory).toBe(false);
    });

    it('should return empty array for empty directory', async () => {
      (FileSystem.readDirectoryAsync as jest.Mock).mockResolvedValueOnce([]);

      const result = await FileSystemService.listFiles('/empty');

      expect(result).toEqual([]);
    });

    it('should throw FileSystemError when directory does not exist', async () => {
      (FileSystem.readDirectoryAsync as jest.Mock).mockRejectedValueOnce(new Error('ENOENT: no such file or directory'));

      await expect(FileSystemService.listFiles('/nonexistent')).rejects.toThrow(FileSystemError);
    });
  });

  describe('readFile', () => {
    it('should read file contents as string', async () => {
      const filePath = '/vault/file.md';
      const content = '# Hello World';
      
      (FileSystem.readAsStringAsync as jest.Mock).mockResolvedValueOnce(content);

      const result = await FileSystemService.readFile(filePath);

      expect(result).toBe(content);
      expect(FileSystem.readAsStringAsync).toHaveBeenCalledWith('file:///vault/file.md', { encoding: FileSystem.EncodingType.UTF8 });
    });

    it('should read file contents as buffer when specified', async () => {
      const filePath = '/vault/image.png';
      const content = 'binary content';
      
      (FileSystem.readAsStringAsync as jest.Mock).mockResolvedValueOnce(content);

      const result = await FileSystemService.readFile(filePath, 'buffer');

      expect(result).toBeInstanceOf(Uint8Array);
    });

    it('should throw FileSystemError when file does not exist', async () => {
      (FileSystem.readAsStringAsync as jest.Mock).mockRejectedValueOnce(new Error('ENOENT: no such file or directory'));

      await expect(FileSystemService.readFile('/nonexistent/file.md')).rejects.toThrow(FileSystemError);
    });
  });

  describe('writeFile', () => {
    it('should write string content to file', async () => {
      const filePath = '/vault/file.md';
      const content = '# New Content';
      
      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValue({ exists: true, isDirectory: true });
      (FileSystem.writeAsStringAsync as jest.Mock).mockResolvedValueOnce(undefined);

      await FileSystemService.writeFile(filePath, content);

      expect(FileSystem.writeAsStringAsync).toHaveBeenCalledWith('file:///vault/file.md', content, { encoding: FileSystem.EncodingType.UTF8 });
    });

    it('should create parent directories if they do not exist', async () => {
      const filePath = '/vault/folder/subfolder/file.md';
      const content = '# Content';
      
      // Mock directory checks and creations
      (FileSystem.getInfoAsync as jest.Mock)
        .mockResolvedValueOnce({ exists: false }) // /vault/folder/subfolder doesn't exist
        .mockResolvedValueOnce({ exists: true, isDirectory: true }); // after creation
      
      (FileSystem.writeAsStringAsync as jest.Mock).mockResolvedValueOnce(undefined);

      await FileSystemService.writeFile(filePath, content);

      expect(FileSystem.makeDirectoryAsync).toHaveBeenCalledWith('file:///vault/folder/subfolder', { intermediates: true });
    });

    it('should write buffer content', async () => {
      const filePath = '/vault/image.png';
      const buffer = new Uint8Array([1, 2, 3, 4]);
      
      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValue({ exists: true, isDirectory: true });
      (FileSystem.writeAsStringAsync as jest.Mock).mockResolvedValueOnce(undefined);

      await FileSystemService.writeFile(filePath, buffer);

      // Verify that writeFile was called
      expect(FileSystem.writeAsStringAsync).toHaveBeenCalled();
    });

    it('should throw FileSystemError on write failure', async () => {
      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValue({ exists: true, isDirectory: true });
      (FileSystem.writeAsStringAsync as jest.Mock).mockRejectedValueOnce(new Error('EACCES: permission denied'));

      await expect(FileSystemService.writeFile('/readonly/file.md', 'content')).rejects.toThrow(FileSystemError);
    });
  });

  describe('deleteFile', () => {
    it('should delete a file', async () => {
      const filePath = '/vault/file.md';
      
      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValueOnce({ exists: true, isDirectory: false });
      (FileSystem.deleteAsync as jest.Mock).mockResolvedValueOnce(undefined);

      await FileSystemService.deleteFile(filePath);

      expect(FileSystem.deleteAsync).toHaveBeenCalledWith('file:///vault/file.md', { idempotent: true });
    });

    it('should throw FileSystemError when deleting a directory', async () => {
      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValueOnce({ exists: true, isDirectory: true });

      await expect(FileSystemService.deleteFile('/vault/folder')).rejects.toThrow(FileSystemError);
    });

    it('should throw FileSystemError when file does not exist', async () => {
      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValueOnce({ exists: false });

      await expect(FileSystemService.deleteFile('/nonexistent/file.md')).rejects.toThrow(FileSystemError);
    });
  });

  describe('createDirectory', () => {
    it('should create a new directory', async () => {
      const dirPath = '/vault/new-folder';
      
      (FileSystem.makeDirectoryAsync as jest.Mock).mockResolvedValueOnce(undefined);

      await FileSystemService.createDirectory(dirPath);

      expect(FileSystem.makeDirectoryAsync).toHaveBeenCalledWith('file:///vault/new-folder', { intermediates: false });
    });

    it('should create nested directories recursively', async () => {
      const dirPath = '/vault/parent/child/grandchild';
      
      (FileSystem.makeDirectoryAsync as jest.Mock).mockResolvedValue(undefined);

      await FileSystemService.createDirectory(dirPath, { recursive: true });

      expect(FileSystem.makeDirectoryAsync).toHaveBeenCalledWith('file:///vault/parent/child/grandchild', { intermediates: true });
    });

    it('should throw FileSystemError when parent directory does not exist', async () => {
      (FileSystem.makeDirectoryAsync as jest.Mock).mockRejectedValueOnce(new Error('ENOENT'));

      await expect(FileSystemService.createDirectory('/nonexistent/folder')).rejects.toThrow(FileSystemError);
    });
  });

  describe('deleteDirectory', () => {
    it('should delete an empty directory', async () => {
      const dirPath = '/vault/empty-folder';
      
      (FileSystem.deleteAsync as jest.Mock).mockResolvedValueOnce(undefined);

      await FileSystemService.deleteDirectory(dirPath);

      expect(FileSystem.deleteAsync).toHaveBeenCalledWith('file:///vault/empty-folder', { idempotent: true });
    });

    it('should delete directory recursively with contents', async () => {
      const dirPath = '/vault/folder';
      
      (FileSystem.deleteAsync as jest.Mock).mockResolvedValueOnce(undefined);

      await FileSystemService.deleteDirectory(dirPath, { recursive: true });

      expect(FileSystem.deleteAsync).toHaveBeenCalledWith('file:///vault/folder', { idempotent: true });
    });

    it('should throw FileSystemError when directory does not exist', async () => {
      (FileSystem.deleteAsync as jest.Mock).mockRejectedValueOnce(new Error('ENOENT'));

      await expect(FileSystemService.deleteDirectory('/nonexistent')).rejects.toThrow(FileSystemError);
    });
  });

  describe('exists', () => {
    it('should return true when file exists', async () => {
      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValueOnce({ exists: true, isDirectory: false });

      const result = await FileSystemService.exists('/vault/file.md');

      expect(result).toBe(true);
    });

    it('should return true when directory exists', async () => {
      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValueOnce({ exists: true, isDirectory: true });

      const result = await FileSystemService.exists('/vault/folder');

      expect(result).toBe(true);
    });

    it('should return false when path does not exist', async () => {
      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValueOnce({ exists: false });

      const result = await FileSystemService.exists('/nonexistent');

      expect(result).toBe(false);
    });
  });

  describe('isDirectory', () => {
    it('should return true for directory', async () => {
      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValueOnce({ exists: true, isDirectory: true });

      const result = await FileSystemService.isDirectory('/vault/folder');

      expect(result).toBe(true);
    });

    it('should return false for file', async () => {
      (FileSystem.getInfoAsync as jest.Mock).mockResolvedValueOnce({ exists: true, isDirectory: false });

      const result = await FileSystemService.isDirectory('/vault/file.md');

      expect(result).toBe(false);
    });

    it('should throw FileSystemError when path does not exist', async () => {
      (FileSystem.getInfoAsync as jest.Mock).mockRejectedValueOnce(new Error('ENOENT'));

      await expect(FileSystemService.isDirectory('/nonexistent')).rejects.toThrow(FileSystemError);
    });
  });

  describe('getFileTree', () => {
    it('should return structured file tree data', async () => {
      const rootPath = '/vault';
      
      (FileSystem.readDirectoryAsync as jest.Mock)
        .mockResolvedValueOnce(['readme.md', 'src'])
        .mockResolvedValueOnce(['index.ts', 'utils'])
        .mockResolvedValueOnce(['helper.ts']);
      
      (FileSystem.getInfoAsync as jest.Mock)
        .mockResolvedValueOnce({ exists: true, isDirectory: false, size: 100 })
        .mockResolvedValueOnce({ exists: true, isDirectory: true, size: 0 })
        .mockResolvedValueOnce({ exists: true, isDirectory: false, size: 200 })
        .mockResolvedValueOnce({ exists: true, isDirectory: true, size: 0 })
        .mockResolvedValueOnce({ exists: true, isDirectory: false, size: 300 });

      const result = await FileSystemService.getFileTree(rootPath);

      expect(result.path).toBe('file:///vault');
      expect(result.name).toBe('vault');
      expect(result.isDirectory).toBe(true);
      expect(result.children).toHaveLength(2);
    });

    it('should handle empty root directory', async () => {
      (FileSystem.readDirectoryAsync as jest.Mock).mockResolvedValueOnce([]);

      const result = await FileSystemService.getFileTree('/vault');

      expect(result.children).toEqual([]);
    });
  });

  describe('Error Handling', () => {
    describe('FileSystemError', () => {
      it('should create error with specific type', () => {
        const error = new FileSystemError('File not found', FileSystemErrorType.NOT_FOUND);
        
        expect(error.message).toBe('File not found');
        expect(error.type).toBe(FileSystemErrorType.NOT_FOUND);
        expect(error).toBeInstanceOf(Error);
      });

      it('should include original error if provided', () => {
        const original = new Error('Original error');
        const error = new FileSystemError('File not found', FileSystemErrorType.NOT_FOUND, original);
        
        expect(error.originalError).toBe(original);
      });

      it('should have all error types', () => {
        expect(FileSystemErrorType.NOT_FOUND).toBe('NOT_FOUND');
        expect(FileSystemErrorType.PERMISSION_DENIED).toBe('PERMISSION_DENIED');
        expect(FileSystemErrorType.IS_DIRECTORY).toBe('IS_DIRECTORY');
        expect(FileSystemErrorType.NOT_DIRECTORY).toBe('NOT_DIRECTORY');
        expect(FileSystemErrorType.DIRECTORY_NOT_EMPTY).toBe('DIRECTORY_NOT_EMPTY');
        expect(FileSystemErrorType.UNKNOWN).toBe('UNKNOWN');
      });
    });
  });

  describe('Path Utilities', () => {
    describe('join', () => {
      it('should join path segments', () => {
        const result = FileSystemService.join('vault', 'folder', 'file.md');
        
        expect(result).toBe('/vault/folder/file.md');
      });

      it('should handle leading slash', () => {
        const result = FileSystemService.join('/vault', 'folder', 'file.md');
        
        expect(result).toBe('/vault/folder/file.md');
      });

      it('should handle trailing slashes', () => {
        const result = FileSystemService.join('vault/', '/folder/', 'file.md');
        
        expect(result).toBe('/vault/folder/file.md');
      });
    });

    describe('dirname', () => {
      it('should return directory name', () => {
        const result = FileSystemService.dirname('/vault/folder/file.md');
        
        expect(result).toBe('/vault/folder');
      });

      it('should handle root path', () => {
        const result = FileSystemService.dirname('/file.md');
        
        expect(result).toBe('/');
      });
    });

    describe('basename', () => {
      it('should return file name with extension', () => {
        const result = FileSystemService.basename('/vault/folder/file.md');
        
        expect(result).toBe('file.md');
      });

      it('should return directory name', () => {
        const result = FileSystemService.basename('/vault/folder');
        
        expect(result).toBe('folder');
      });
    });
  });
});
