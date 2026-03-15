import { FileSystemService, FileSystemError, FileSystemErrorType, FileNode } from '../../src/services/fileSystemService';
import LightningFS from '@isomorphic-git/lightning-fs';

// Mock LightningFS
jest.mock('@isomorphic-git/lightning-fs');

describe('FileSystemService', () => {
  let mockPfs: any;

  beforeEach(() => {
    jest.clearAllMocks();
    
    mockPfs = {
      mkdir: jest.fn(() => Promise.resolve()),
      readdir: jest.fn(() => Promise.resolve([])),
      readFile: jest.fn(() => Promise.resolve('')),
      writeFile: jest.fn(() => Promise.resolve()),
      unlink: jest.fn(() => Promise.resolve()),
      rmdir: jest.fn(() => Promise.resolve()),
      stat: jest.fn(() => Promise.resolve({ type: 'file', size: 100, mtimeMs: Date.now() })),
      lstat: jest.fn(() => Promise.resolve({ type: 'file', size: 100, mtimeMs: Date.now() })),
    };
    
    (LightningFS as jest.MockedClass<typeof LightningFS>).mockImplementation(() => ({
      promises: mockPfs,
    }) as any);
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
      
      mockPfs.readdir.mockResolvedValueOnce([
        { name: 'file1.md', type: 'file' },
        { name: 'folder1', type: 'directory' },
      ]);
      
      mockPfs.readdir.mockResolvedValueOnce([
        { name: 'file2.md', type: 'file' },
      ]);

      const result = await FileSystemService.listFiles(rootPath);

      expect(result).toHaveLength(2);
      expect(result[0].name).toBe('file1.md');
      expect(result[0].isDirectory).toBe(false);
      expect(result[1].name).toBe('folder1');
      expect(result[1].isDirectory).toBe(true);
      expect(result[1].children).toHaveLength(1);
    });

    it('should return empty array for empty directory', async () => {
      mockPfs.readdir.mockResolvedValueOnce([]);

      const result = await FileSystemService.listFiles('/empty');

      expect(result).toEqual([]);
    });

    it('should throw FileSystemError when directory does not exist', async () => {
      mockPfs.readdir.mockRejectedValueOnce(new Error('ENOENT: no such file or directory'));

      await expect(FileSystemService.listFiles('/nonexistent')).rejects.toThrow(FileSystemError);
    });
  });

  describe('readFile', () => {
    it('should read file contents as string', async () => {
      const filePath = '/vault/file.md';
      const content = '# Hello World';
      
      mockPfs.readFile.mockResolvedValueOnce(content);

      const result = await FileSystemService.readFile(filePath);

      expect(result).toBe(content);
      expect(mockPfs.readFile).toHaveBeenCalledWith(filePath, 'utf8');
    });

    it('should read file contents as buffer when specified', async () => {
      const filePath = '/vault/image.png';
      const buffer = Buffer.from([1, 2, 3, 4]);
      
      mockPfs.readFile.mockResolvedValueOnce(buffer);

      const result = await FileSystemService.readFile(filePath, 'buffer');

      expect(result).toEqual(buffer);
    });

    it('should throw FileSystemError when file does not exist', async () => {
      mockPfs.readFile.mockRejectedValueOnce(new Error('ENOENT: no such file or directory'));

      await expect(FileSystemService.readFile('/nonexistent/file.md')).rejects.toThrow(FileSystemError);
    });

    it('should throw FileSystemError when path is a directory', async () => {
      mockPfs.readFile.mockRejectedValueOnce(new Error('EISDIR: illegal operation on a directory'));

      await expect(FileSystemService.readFile('/vault/folder')).rejects.toThrow(FileSystemError);
    });
  });

  describe('writeFile', () => {
    it('should write string content to file', async () => {
      const filePath = '/vault/file.md';
      const content = '# New Content';
      
      mockPfs.writeFile.mockResolvedValueOnce(undefined);

      await FileSystemService.writeFile(filePath, content);

      expect(mockPfs.writeFile).toHaveBeenCalledWith(filePath, content, 'utf8');
    });

    it('should create parent directories if they do not exist', async () => {
      const filePath = '/vault/folder/subfolder/file.md';
      const content = '# Content';
      
      // Mock exists to return false for directories that don't exist
      mockPfs.stat
        .mockRejectedValueOnce(new Error('ENOENT'))  // /vault/folder/subfolder doesn't exist
        .mockRejectedValueOnce(new Error('ENOENT'))  // /vault doesn't exist (in recursive)
        .mockRejectedValueOnce(new Error('ENOENT'))  // /vault/folder doesn't exist (in recursive)
        .mockRejectedValueOnce(new Error('ENOENT'))  // /vault/folder/subfolder doesn't exist (in recursive)
        .mockResolvedValueOnce({ type: 'directory' }); // after creation
      
      mockPfs.mkdir.mockResolvedValue(undefined);
      mockPfs.writeFile.mockResolvedValueOnce(undefined);

      await FileSystemService.writeFile(filePath, content);

      expect(mockPfs.mkdir).toHaveBeenCalledWith('/vault');
      expect(mockPfs.mkdir).toHaveBeenCalledWith('/vault/folder');
      expect(mockPfs.mkdir).toHaveBeenCalledWith('/vault/folder/subfolder');
    });

    it('should write buffer content', async () => {
      const filePath = '/vault/image.png';
      const buffer = Buffer.from([1, 2, 3, 4]);
      
      mockPfs.writeFile.mockResolvedValueOnce(undefined);

      await FileSystemService.writeFile(filePath, buffer);

      // Verify that writeFile was called with the correct file path and content
      const callArgs = mockPfs.writeFile.mock.calls[0];
      expect(callArgs[0]).toBe(filePath);
      expect(Buffer.isBuffer(callArgs[1])).toBe(true);
      expect(callArgs[2]).toBeUndefined();
    });

    it('should throw FileSystemError on write failure', async () => {
      mockPfs.writeFile.mockRejectedValueOnce(new Error('EACCES: permission denied'));

      await expect(FileSystemService.writeFile('/readonly/file.md', 'content')).rejects.toThrow(FileSystemError);
    });
  });

  describe('deleteFile', () => {
    it('should delete a file', async () => {
      const filePath = '/vault/file.md';
      
      mockPfs.stat.mockResolvedValueOnce({ type: 'file' });
      mockPfs.unlink.mockResolvedValueOnce(undefined);

      await FileSystemService.deleteFile(filePath);

      expect(mockPfs.unlink).toHaveBeenCalledWith(filePath);
    });

    it('should throw FileSystemError when deleting a directory', async () => {
      mockPfs.stat.mockResolvedValueOnce({ type: 'directory' });

      await expect(FileSystemService.deleteFile('/vault/folder')).rejects.toThrow(FileSystemError);
    });

    it('should throw FileSystemError when file does not exist', async () => {
      mockPfs.stat.mockRejectedValueOnce(new Error('ENOENT'));

      await expect(FileSystemService.deleteFile('/nonexistent/file.md')).rejects.toThrow(FileSystemError);
    });
  });

  describe('createDirectory', () => {
    it('should create a new directory', async () => {
      const dirPath = '/vault/new-folder';
      
      mockPfs.mkdir.mockResolvedValueOnce(undefined);

      await FileSystemService.createDirectory(dirPath);

      expect(mockPfs.mkdir).toHaveBeenCalledWith(dirPath);
    });

    it('should create nested directories recursively', async () => {
      const dirPath = '/vault/parent/child/grandchild';
      
      // Mock exists to return false for all directories
      mockPfs.stat
        .mockRejectedValueOnce(new Error('ENOENT'))  // /vault doesn't exist
        .mockRejectedValueOnce(new Error('ENOENT'))  // /vault/parent doesn't exist
        .mockRejectedValueOnce(new Error('ENOENT'))  // /vault/parent/child doesn't exist
        .mockRejectedValueOnce(new Error('ENOENT'))  // /vault/parent/child/grandchild doesn't exist
        .mockResolvedValueOnce({ type: 'directory' }); // after creation
      
      mockPfs.mkdir.mockResolvedValue(undefined);

      await FileSystemService.createDirectory(dirPath, { recursive: true });

      expect(mockPfs.mkdir).toHaveBeenCalledWith('/vault');
      expect(mockPfs.mkdir).toHaveBeenCalledWith('/vault/parent');
      expect(mockPfs.mkdir).toHaveBeenCalledWith('/vault/parent/child');
      expect(mockPfs.mkdir).toHaveBeenCalledWith(dirPath);
    });

    it('should throw FileSystemError when parent directory does not exist', async () => {
      mockPfs.mkdir.mockRejectedValueOnce(new Error('ENOENT'));

      await expect(FileSystemService.createDirectory('/nonexistent/folder')).rejects.toThrow(FileSystemError);
    });
  });

  describe('deleteDirectory', () => {
    it('should delete an empty directory', async () => {
      const dirPath = '/vault/empty-folder';
      
      mockPfs.readdir.mockResolvedValueOnce([]);
      mockPfs.rmdir.mockResolvedValueOnce(undefined);

      await FileSystemService.deleteDirectory(dirPath);

      expect(mockPfs.rmdir).toHaveBeenCalledWith(dirPath);
    });

    it('should delete directory recursively with contents', async () => {
      const dirPath = '/vault/folder';
      
      mockPfs.readdir.mockResolvedValueOnce([
        { name: 'file.md', type: 'file' },
        { name: 'subfolder', type: 'directory' },
      ]);
      
      mockPfs.readdir.mockResolvedValueOnce([
        { name: 'nested.md', type: 'file' },
      ]);

      await FileSystemService.deleteDirectory(dirPath, { recursive: true });

      expect(mockPfs.unlink).toHaveBeenCalledWith('/vault/folder/file.md');
      expect(mockPfs.unlink).toHaveBeenCalledWith('/vault/folder/subfolder/nested.md');
      expect(mockPfs.rmdir).toHaveBeenCalledWith('/vault/folder/subfolder');
      expect(mockPfs.rmdir).toHaveBeenCalledWith(dirPath);
    });

    it('should throw FileSystemError when directory is not empty', async () => {
      mockPfs.readdir.mockResolvedValueOnce([{ name: 'file.md', type: 'file' }]);

      await expect(FileSystemService.deleteDirectory('/vault/folder')).rejects.toThrow(FileSystemError);
    });

    it('should throw FileSystemError when directory does not exist', async () => {
      mockPfs.readdir.mockRejectedValueOnce(new Error('ENOENT'));

      await expect(FileSystemService.deleteDirectory('/nonexistent')).rejects.toThrow(FileSystemError);
    });
  });

  describe('exists', () => {
    it('should return true when file exists', async () => {
      mockPfs.stat.mockResolvedValueOnce({ type: 'file' });

      const result = await FileSystemService.exists('/vault/file.md');

      expect(result).toBe(true);
    });

    it('should return true when directory exists', async () => {
      mockPfs.stat.mockResolvedValueOnce({ type: 'directory' });

      const result = await FileSystemService.exists('/vault/folder');

      expect(result).toBe(true);
    });

    it('should return false when path does not exist', async () => {
      mockPfs.stat.mockRejectedValueOnce(new Error('ENOENT'));

      const result = await FileSystemService.exists('/nonexistent');

      expect(result).toBe(false);
    });
  });

  describe('isDirectory', () => {
    it('should return true for directory', async () => {
      mockPfs.stat.mockResolvedValueOnce({ type: 'directory' });

      const result = await FileSystemService.isDirectory('/vault/folder');

      expect(result).toBe(true);
    });

    it('should return false for file', async () => {
      mockPfs.stat.mockResolvedValueOnce({ type: 'file' });

      const result = await FileSystemService.isDirectory('/vault/file.md');

      expect(result).toBe(false);
    });

    it('should throw FileSystemError when path does not exist', async () => {
      mockPfs.stat.mockRejectedValueOnce(new Error('ENOENT'));

      await expect(FileSystemService.isDirectory('/nonexistent')).rejects.toThrow(FileSystemError);
    });
  });

  describe('getFileTree', () => {
    it('should return structured file tree data', async () => {
      const rootPath = '/vault';
      
      mockPfs.readdir.mockResolvedValueOnce([
        { name: 'readme.md', type: 'file' },
        { name: 'src', type: 'directory' },
      ]);
      
      mockPfs.readdir.mockResolvedValueOnce([
        { name: 'index.ts', type: 'file' },
        { name: 'utils', type: 'directory' },
      ]);
      
      mockPfs.readdir.mockResolvedValueOnce([
        { name: 'helper.ts', type: 'file' },
      ]);

      const result = await FileSystemService.getFileTree(rootPath);

      expect(result.path).toBe(rootPath);
      expect(result.name).toBe('vault');
      expect(result.isDirectory).toBe(true);
      expect(result.children).toHaveLength(2);
      expect(result.children![0].name).toBe('readme.md');
      expect(result.children![0].isDirectory).toBe(false);
      expect(result.children![1].name).toBe('src');
      expect(result.children![1].isDirectory).toBe(true);
      expect(result.children![1].children).toHaveLength(2);
    });

    it('should handle empty root directory', async () => {
      mockPfs.readdir.mockResolvedValueOnce([]);

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
