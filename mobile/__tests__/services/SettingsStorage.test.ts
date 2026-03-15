import AsyncStorage from '@react-native-async-storage/async-storage';
import { SettingsStorage, DailyNoteSettings } from '../../src/services/SettingsStorage';

// Mock AsyncStorage
jest.mock('@react-native-async-storage/async-storage', () => ({
  setItem: jest.fn(),
  getItem: jest.fn(),
  removeItem: jest.fn(),
}));

const mockedSetItem = AsyncStorage.setItem as jest.Mock;
const mockedGetItem = AsyncStorage.getItem as jest.Mock;

describe('SettingsStorage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('dailyNotesEnabled', () => {
    it('should default to false', async () => {
      // Test will fail initially - Storage not implemented
      mockedGetItem.mockResolvedValue(null);
      
      const enabled = await SettingsStorage.getDailyNotesEnabled();
      
      expect(enabled).toBe(false);
    });

    it('should persist and retrieve value', async () => {
      // Test will fail initially
      await SettingsStorage.setDailyNotesEnabled(true);
      mockedGetItem.mockResolvedValue('true');
      
      const enabled = await SettingsStorage.getDailyNotesEnabled();
      
      expect(mockedSetItem).toHaveBeenCalledWith('dailyNotesEnabled', 'true');
      expect(enabled).toBe(true);
    });

    it('should default to false when storage returns null', async () => {
      mockedGetItem.mockResolvedValue(null);
      
      const enabled = await SettingsStorage.getDailyNotesEnabled();
      
      expect(enabled).toBe(false);
    });
  });

  describe('dailyNotesFolder', () => {
    it('should default to "daily"', async () => {
      mockedGetItem.mockResolvedValue(null);
      
      const folder = await SettingsStorage.getDailyNotesFolder();
      
      expect(folder).toBe('daily');
    });

    it('should persist custom folder name', async () => {
      await SettingsStorage.setDailyNotesFolder('journal');
      mockedGetItem.mockResolvedValue('journal');
      
      const folder = await SettingsStorage.getDailyNotesFolder();
      
      expect(mockedSetItem).toHaveBeenCalledWith('dailyNotesFolder', 'journal');
      expect(folder).toBe('journal');
    });
  });

  describe('dailyNotesTemplate', () => {
    it('should default to empty string', async () => {
      mockedGetItem.mockResolvedValue(null);
      
      const template = await SettingsStorage.getDailyNotesTemplate();
      
      expect(template).toBe('');
    });

    it('should persist template name', async () => {
      await SettingsStorage.setDailyNotesTemplate('daily.md');
      mockedGetItem.mockResolvedValue('daily.md');
      
      const template = await SettingsStorage.getDailyNotesTemplate();
      
      expect(mockedSetItem).toHaveBeenCalledWith('dailyNotesTemplate', 'daily.md');
      expect(template).toBe('daily.md');
    });
  });

  describe('dailyNotesOpenOnStartup', () => {
    it('should default to false', async () => {
      mockedGetItem.mockResolvedValue(null);
      
      const openOnStartup = await SettingsStorage.getDailyNotesOpenOnStartup();
      
      expect(openOnStartup).toBe(false);
    });

    it('should persist and retrieve value', async () => {
      await SettingsStorage.setDailyNotesOpenOnStartup(true);
      mockedGetItem.mockResolvedValue('true');
      
      const openOnStartup = await SettingsStorage.getDailyNotesOpenOnStartup();
      
      expect(mockedSetItem).toHaveBeenCalledWith('dailyNotesOpenOnStartup', 'true');
      expect(openOnStartup).toBe(true);
    });
  });

  describe('getAllDailyNoteSettings', () => {
    it('should return all settings as an object', async () => {
      mockedGetItem
        .mockResolvedValueOnce('true')  // dailyNotesEnabled
        .mockResolvedValueOnce('journal')  // dailyNotesFolder
        .mockResolvedValueOnce('template.md')  // dailyNotesTemplate
        .mockResolvedValueOnce('true');  // dailyNotesOpenOnStartup
      
      const settings: DailyNoteSettings = await SettingsStorage.getAllDailyNoteSettings();
      
      expect(settings).toEqual({
        dailyNotesEnabled: true,
        dailyNotesFolder: 'journal',
        dailyNotesTemplate: 'template.md',
        dailyNotesOpenOnStartup: true,
      });
    });

    it('should return defaults when no settings exist', async () => {
      mockedGetItem.mockResolvedValue(null);
      
      const settings: DailyNoteSettings = await SettingsStorage.getAllDailyNoteSettings();
      
      expect(settings).toEqual({
        dailyNotesEnabled: false,
        dailyNotesFolder: 'daily',
        dailyNotesTemplate: '',
        dailyNotesOpenOnStartup: false,
      });
    });
  });
});
