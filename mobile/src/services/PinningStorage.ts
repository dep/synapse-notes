import AsyncStorage from '@react-native-async-storage/async-storage';
import { FileSystemService } from './FileSystemService';

export interface PinnedItem {
  id: string;
  path: string;
  name: string;
  isFolder: boolean;
  vaultPath: string;
}

const STORAGE_KEY_PREFIX = 'pinned_items_';

export class PinningStorage {
  private static getStorageKey(vaultPath: string): string {
    // Create a safe key from vault path
    const safePath = vaultPath.replace(/[^a-zA-Z0-9]/g, '_');
    return `${STORAGE_KEY_PREFIX}${safePath}`;
  }

  static async getPinnedItems(vaultPath: string): Promise<PinnedItem[]> {
    try {
      const key = this.getStorageKey(vaultPath);
      const json = await AsyncStorage.getItem(key);
      if (!json) return [];
      
      const items: PinnedItem[] = JSON.parse(json);
      
      // Filter out items that no longer exist
      const existingItems: PinnedItem[] = [];
      for (const item of items) {
        const exists = await FileSystemService.exists(item.path);
        if (exists) {
          existingItems.push(item);
        }
      }
      
      // If some items were filtered out, update storage
      if (existingItems.length !== items.length) {
        await AsyncStorage.setItem(key, JSON.stringify(existingItems));
      }
      
      return existingItems;
    } catch (error) {
      console.error('Failed to get pinned items:', error);
      return [];
    }
  }

  static async pinItem(path: string, name: string, isFolder: boolean, vaultPath: string): Promise<void> {
    try {
      const items = await this.getPinnedItems(vaultPath);
      
      // Check if already pinned
      if (items.some(item => item.path === path)) {
        return;
      }
      
      const newItem: PinnedItem = {
        id: `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        path,
        name,
        isFolder,
        vaultPath,
      };
      
      const updatedItems = [...items, newItem];
      const key = this.getStorageKey(vaultPath);
      await AsyncStorage.setItem(key, JSON.stringify(updatedItems));
    } catch (error) {
      console.error('Failed to pin item:', error);
      throw error;
    }
  }

  static async unpinItem(path: string, vaultPath: string): Promise<void> {
    try {
      const items = await this.getPinnedItems(vaultPath);
      const updatedItems = items.filter(item => item.path !== path);
      
      const key = this.getStorageKey(vaultPath);
      await AsyncStorage.setItem(key, JSON.stringify(updatedItems));
    } catch (error) {
      console.error('Failed to unpin item:', error);
      throw error;
    }
  }

  static async isPinned(path: string, vaultPath: string): Promise<boolean> {
    try {
      const items = await this.getPinnedItems(vaultPath);
      return items.some(item => item.path === path);
    } catch (error) {
      console.error('Failed to check if item is pinned:', error);
      return false;
    }
  }

  static async clearAllPins(vaultPath: string): Promise<void> {
    try {
      const key = this.getStorageKey(vaultPath);
      await AsyncStorage.removeItem(key);
    } catch (error) {
      console.error('Failed to clear pinned items:', error);
      throw error;
    }
  }
}
