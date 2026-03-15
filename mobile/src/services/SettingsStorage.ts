import AsyncStorage from '@react-native-async-storage/async-storage';

export interface DailyNoteSettings {
  dailyNotesEnabled: boolean;
  dailyNotesFolder: string;
  dailyNotesTemplate: string;
  dailyNotesOpenOnStartup: boolean;
}

export interface FileBrowserSettings {
  fileExtensionFilter: string;
  hiddenFileFolderFilter: string;
}

const STORAGE_KEYS = {
  DAILY_NOTES_ENABLED: 'dailyNotesEnabled',
  DAILY_NOTES_FOLDER: 'dailyNotesFolder',
  DAILY_NOTES_TEMPLATE: 'dailyNotesTemplate',
  DAILY_NOTES_OPEN_ON_STARTUP: 'dailyNotesOpenOnStartup',
  FILE_EXTENSION_FILTER: 'fileExtensionFilter',
  HIDDEN_FILE_FOLDER_FILTER: 'hiddenFileFolderFilter',
  SHARE_DEFAULT_FOLDER: 'shareDefaultFolder',
};

const DEFAULTS = {
  dailyNotesEnabled: false,
  dailyNotesFolder: 'daily',
  dailyNotesTemplate: '',
  dailyNotesOpenOnStartup: false,
  fileExtensionFilter: '*.md, *.txt',
  hiddenFileFolderFilter: '',
  shareDefaultFolder: '',
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

  // fileExtensionFilter
  static async getFileExtensionFilter(): Promise<string> {
    const value = await AsyncStorage.getItem(STORAGE_KEYS.FILE_EXTENSION_FILTER);
    return value ?? DEFAULTS.fileExtensionFilter;
  }

  static async setFileExtensionFilter(filter: string): Promise<void> {
    await AsyncStorage.setItem(STORAGE_KEYS.FILE_EXTENSION_FILTER, filter);
  }

  // hiddenFileFolderFilter
  static async getHiddenFileFolderFilter(): Promise<string> {
    const value = await AsyncStorage.getItem(STORAGE_KEYS.HIDDEN_FILE_FOLDER_FILTER);
    return value ?? DEFAULTS.hiddenFileFolderFilter;
  }

  static async setHiddenFileFolderFilter(filter: string): Promise<void> {
    await AsyncStorage.setItem(STORAGE_KEYS.HIDDEN_FILE_FOLDER_FILTER, filter);
  }

  // shareDefaultFolder
  static async getShareDefaultFolder(): Promise<string> {
    const value = await AsyncStorage.getItem(STORAGE_KEYS.SHARE_DEFAULT_FOLDER);
    return value ?? DEFAULTS.shareDefaultFolder;
  }

  static async setShareDefaultFolder(folder: string): Promise<void> {
    await AsyncStorage.setItem(STORAGE_KEYS.SHARE_DEFAULT_FOLDER, folder);
  }

  // Get all file browser settings at once
  static async getAllFileBrowserSettings(): Promise<FileBrowserSettings> {
    const [fileExtensionFilter, hiddenFileFolderFilter] = await Promise.all([
      AsyncStorage.getItem(STORAGE_KEYS.FILE_EXTENSION_FILTER),
      AsyncStorage.getItem(STORAGE_KEYS.HIDDEN_FILE_FOLDER_FILTER),
    ]);

    return {
      fileExtensionFilter: fileExtensionFilter ?? DEFAULTS.fileExtensionFilter,
      hiddenFileFolderFilter: hiddenFileFolderFilter ?? DEFAULTS.hiddenFileFolderFilter,
    };
  }
}
