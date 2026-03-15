import { FileSystemService } from '../../src/services/FileSystemService';

// Mock expo-file-system
jest.mock('expo-file-system', () => ({
  documentDirectory: 'file:///mock/documents/',
  EncodingType: {
    UTF8: 'utf8',
    Base64: 'base64',
  },
  readAsStringAsync: jest.fn(),
  writeAsStringAsync: jest.fn(),
  readDirectoryAsync: jest.fn(),
  getInfoAsync: jest.fn(),
  makeDirectoryAsync: jest.fn(),
  deleteAsync: jest.fn(),
  copyAsync: jest.fn(),
}));

describe('FileSystemService', () => {
  afterEach(() => {
    FileSystemService.clearInstance();
  });

  describe('Singleton pattern', () => {
    it('should return same instance', () => {
      const instance1 = FileSystemService.getInstance();
      const instance2 = FileSystemService.getInstance();

      expect(instance1).toBe(instance2);
    });

    it('should create new instance after clearInstance', () => {
      const instance1 = FileSystemService.getInstance();
      FileSystemService.clearInstance();
      const instance2 = FileSystemService.getInstance();

      expect(instance1).not.toBe(instance2);
    });
  });

  // Note: Full file operation tests are done via integration testing
  // The service is a thin wrapper around expo-file-system
});
