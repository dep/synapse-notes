import AsyncStorage from '@react-native-async-storage/async-storage';
import { PinningStorage, PinnedItem } from '../../src/services/PinningStorage';
import { FileSystemService } from '../../src/services/FileSystemService';

// Mock AsyncStorage
jest.mock('@react-native-async-storage/async-storage', () => ({
  setItem: jest.fn(),
  getItem: jest.fn(),
  removeItem: jest.fn(),
}));

// Mock FileSystemService
jest.mock('../../src/services/FileSystemService', () => ({
  FileSystemService: {
    exists: jest.fn(),
  },
}));

const mockedSetItem = AsyncStorage.setItem as jest.Mock;
const mockedGetItem = AsyncStorage.getItem as jest.Mock;
const mockedRemoveItem = AsyncStorage.removeItem as jest.Mock;
const mockedExists = FileSystemService.exists as jest.Mock;

describe('PinningStorage', () => {
  const vaultPath = 'file:///documents/vault';
  
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('getPinnedItems', () => {
    it('should return empty array when no pinned items exist', async () => {
      mockedGetItem.mockResolvedValue(null);
      
      const items = await PinningStorage.getPinnedItems(vaultPath);
      
      expect(items).toEqual([]);
    });

    it('should return pinned items that exist', async () => {
      const pinnedItems: PinnedItem[] = [
        { id: '1', path: 'file:///documents/vault/file1.md', name: 'file1.md', isFolder: false, vaultPath },
        { id: '2', path: 'file:///documents/vault/folder1', name: 'folder1', isFolder: true, vaultPath },
      ];
      mockedGetItem.mockResolvedValue(JSON.stringify(pinnedItems));
      mockedExists.mockResolvedValue(true);
      
      const items = await PinningStorage.getPinnedItems(vaultPath);
      
      expect(items).toHaveLength(2);
      expect(items[0].name).toBe('file1.md');
      expect(items[1].name).toBe('folder1');
    });

    it('should filter out items that no longer exist', async () => {
      const pinnedItems: PinnedItem[] = [
        { id: '1', path: 'file:///documents/vault/file1.md', name: 'file1.md', isFolder: false, vaultPath },
        { id: '2', path: 'file:///documents/vault/deleted.md', name: 'deleted.md', isFolder: false, vaultPath },
      ];
      mockedGetItem.mockResolvedValue(JSON.stringify(pinnedItems));
      mockedExists
        .mockResolvedValueOnce(true)   // file1.md exists
        .mockResolvedValueOnce(false);  // deleted.md doesn't exist
      
      const items = await PinningStorage.getPinnedItems(vaultPath);
      
      expect(items).toHaveLength(1);
      expect(items[0].name).toBe('file1.md');
      expect(mockedSetItem).toHaveBeenCalled(); // Should update storage with filtered list
    });

    it('should handle errors gracefully', async () => {
      mockedGetItem.mockRejectedValue(new Error('Storage error'));
      
      const items = await PinningStorage.getPinnedItems(vaultPath);
      
      expect(items).toEqual([]);
    });
  });

  describe('pinItem', () => {
    it('should add a new pinned item', async () => {
      mockedGetItem.mockResolvedValue(null);
      
      await PinningStorage.pinItem(
        'file:///documents/vault/file1.md',
        'file1.md',
        false,
        vaultPath
      );
      
      expect(mockedSetItem).toHaveBeenCalled();
      const savedData = JSON.parse(mockedSetItem.mock.calls[0][1]);
      expect(savedData).toHaveLength(1);
      expect(savedData[0].name).toBe('file1.md');
      expect(savedData[0].isFolder).toBe(false);
    });

    it('should not duplicate existing pins', async () => {
      const existingItem: PinnedItem = {
        id: '1',
        path: 'file:///documents/vault/file1.md',
        name: 'file1.md',
        isFolder: false,
        vaultPath,
      };
      mockedGetItem.mockResolvedValue(JSON.stringify([existingItem]));
      mockedExists.mockResolvedValue(true);
      
      await PinningStorage.pinItem(
        'file:///documents/vault/file1.md',
        'file1.md',
        false,
        vaultPath
      );
      
      // Should not call setItem since item is already pinned
      expect(mockedSetItem).not.toHaveBeenCalled();
    });

    it('should add to existing pinned items', async () => {
      const existingItem: PinnedItem = {
        id: '1',
        path: 'file:///documents/vault/file1.md',
        name: 'file1.md',
        isFolder: false,
        vaultPath,
      };
      mockedGetItem.mockResolvedValue(JSON.stringify([existingItem]));
      mockedExists.mockResolvedValue(true);
      
      await PinningStorage.pinItem(
        'file:///documents/vault/file2.md',
        'file2.md',
        false,
        vaultPath
      );
      
      expect(mockedSetItem).toHaveBeenCalled();
      const savedData = JSON.parse(mockedSetItem.mock.calls[0][1]);
      expect(savedData).toHaveLength(2);
    });
  });

  describe('unpinItem', () => {
    it('should remove a pinned item', async () => {
      const pinnedItems: PinnedItem[] = [
        { id: '1', path: 'file:///documents/vault/file1.md', name: 'file1.md', isFolder: false, vaultPath },
        { id: '2', path: 'file:///documents/vault/file2.md', name: 'file2.md', isFolder: false, vaultPath },
      ];
      mockedGetItem.mockResolvedValue(JSON.stringify(pinnedItems));
      mockedExists.mockResolvedValue(true);
      
      await PinningStorage.unpinItem('file:///documents/vault/file1.md', vaultPath);
      
      expect(mockedSetItem).toHaveBeenCalled();
      const savedData = JSON.parse(mockedSetItem.mock.calls[0][1]);
      expect(savedData).toHaveLength(1);
      expect(savedData[0].name).toBe('file2.md');
    });

    it('should handle unpinning non-existent item gracefully', async () => {
      mockedGetItem.mockResolvedValue(null);
      
      await PinningStorage.unpinItem('file:///documents/vault/file1.md', vaultPath);
      
      expect(mockedSetItem).toHaveBeenCalledWith(
        expect.any(String),
        '[]'
      );
    });
  });

  describe('isPinned', () => {
    it('should return true for pinned item', async () => {
      const pinnedItem: PinnedItem = {
        id: '1',
        path: 'file:///documents/vault/file1.md',
        name: 'file1.md',
        isFolder: false,
        vaultPath,
      };
      mockedGetItem.mockResolvedValue(JSON.stringify([pinnedItem]));
      mockedExists.mockResolvedValue(true);
      
      const result = await PinningStorage.isPinned('file:///documents/vault/file1.md', vaultPath);
      
      expect(result).toBe(true);
    });

    it('should return false for non-pinned item', async () => {
      mockedGetItem.mockResolvedValue(null);
      
      const result = await PinningStorage.isPinned('file:///documents/vault/file1.md', vaultPath);
      
      expect(result).toBe(false);
    });
  });

  describe('clearAllPins', () => {
    it('should remove all pinned items for vault', async () => {
      await PinningStorage.clearAllPins(vaultPath);
      
      expect(mockedRemoveItem).toHaveBeenCalled();
    });
  });

  describe('vault-specific storage', () => {
    it('should use different storage keys for different vaults', async () => {
      const vault1 = 'file:///documents/vault1';
      const vault2 = 'file:///documents/vault2';
      
      mockedGetItem.mockResolvedValue(null);
      
      await PinningStorage.pinItem('file:///file1.md', 'file1.md', false, vault1);
      await PinningStorage.pinItem('file:///file2.md', 'file2.md', false, vault2);
      
      // Should use different storage keys
      const key1 = mockedSetItem.mock.calls[0][0];
      const key2 = mockedSetItem.mock.calls[1][0];
      expect(key1).not.toBe(key2);
    });
  });
});
