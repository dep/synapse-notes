import AsyncStorage from '@react-native-async-storage/async-storage';

export interface DailyNoteSettings {
  dailyNotesEnabled: boolean;
  dailyNotesFolder: string;
  dailyNotesTemplate: string;
  dailyNotesOpenOnStartup: boolean;
}

const STORAGE_KEYS = {
  DAILY_NOTES_ENABLED: 'dailyNotesEnabled',
  DAILY_NOTES_FOLDER: 'dailyNotesFolder',
  DAILY_NOTES_TEMPLATE: 'dailyNotesTemplate',
  DAILY_NOTES_OPEN_ON_STARTUP: 'dailyNotesOpenOnStartup',
};

const DEFAULTS = {
  dailyNotesEnabled: false,
  dailyNotesFolder: 'daily',
  dailyNotesTemplate: '',
  dailyNotesOpenOnStartup: false,
};

export class SettingsStorage {
  // dailyNotesEnabled
  static async getDailyNotesEnabled(): Promise<boolean> {
    const value = await AsyncStorage.getItem(STORAGE_KEYS.DAILY_NOTES_ENABLED);
    return value === 'true';
  }

  static async setDailyNotesEnabled(enabled: boolean): Promise<void> {
    await AsyncStorage.setItem(STORAGE_KEYS.DAILY_NOTES_ENABLED, enabled ? 'true' : 'false');
  }

  // dailyNotesFolder
  static async getDailyNotesFolder(): Promise<string> {
    const value = await AsyncStorage.getItem(STORAGE_KEYS.DAILY_NOTES_FOLDER);
    return value ?? DEFAULTS.dailyNotesFolder;
  }

  static async setDailyNotesFolder(folder: string): Promise<void> {
    await AsyncStorage.setItem(STORAGE_KEYS.DAILY_NOTES_FOLDER, folder);
  }

  // dailyNotesTemplate
  static async getDailyNotesTemplate(): Promise<string> {
    const value = await AsyncStorage.getItem(STORAGE_KEYS.DAILY_NOTES_TEMPLATE);
    return value ?? DEFAULTS.dailyNotesTemplate;
  }

  static async setDailyNotesTemplate(template: string): Promise<void> {
    await AsyncStorage.setItem(STORAGE_KEYS.DAILY_NOTES_TEMPLATE, template);
  }

  // dailyNotesOpenOnStartup
  static async getDailyNotesOpenOnStartup(): Promise<boolean> {
    const value = await AsyncStorage.getItem(STORAGE_KEYS.DAILY_NOTES_OPEN_ON_STARTUP);
    return value === 'true';
  }

  static async setDailyNotesOpenOnStartup(openOnStartup: boolean): Promise<void> {
    await AsyncStorage.setItem(STORAGE_KEYS.DAILY_NOTES_OPEN_ON_STARTUP, openOnStartup ? 'true' : 'false');
  }

  // Get all daily note settings at once
  static async getAllDailyNoteSettings(): Promise<DailyNoteSettings> {
    const [enabled, folder, template, openOnStartup] = await Promise.all([
      AsyncStorage.getItem(STORAGE_KEYS.DAILY_NOTES_ENABLED),
      AsyncStorage.getItem(STORAGE_KEYS.DAILY_NOTES_FOLDER),
      AsyncStorage.getItem(STORAGE_KEYS.DAILY_NOTES_TEMPLATE),
      AsyncStorage.getItem(STORAGE_KEYS.DAILY_NOTES_OPEN_ON_STARTUP),
    ]);

    return {
      dailyNotesEnabled: enabled === 'true',
      dailyNotesFolder: folder ?? DEFAULTS.dailyNotesFolder,
      dailyNotesTemplate: template ?? DEFAULTS.dailyNotesTemplate,
      dailyNotesOpenOnStartup: openOnStartup === 'true',
    };
  }
}
