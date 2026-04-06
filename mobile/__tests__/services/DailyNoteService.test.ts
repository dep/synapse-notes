import { DailyNoteService, DailyNoteResult } from '../../src/services/DailyNoteService';
import { FileSystemService } from '../../src/services/FileSystemService';
import { SettingsStorage } from '../../src/services/SettingsStorage';

// Mock dependencies
jest.mock('../../src/services/FileSystemService', () => ({
  FileSystemService: {
    join: jest.fn((...paths: string[]) => {
      // Simple join implementation for testing
      const firstPath = paths[0];
      if (firstPath?.startsWith('file:///')) {
        const remainingPaths = paths.slice(1).map(p => p.replace(/^\/+|\/+$/g, '')).filter(Boolean);
        if (remainingPaths.length === 0) {
          return firstPath;
        }
        return firstPath.replace(/\/+$/, '') + '/' + remainingPaths.join('/');
      }
      const normalized = paths.map(p => p.replace(/^\/+|\/+$/g, '')).filter(Boolean);
      return '/' + normalized.join('/');
    }),
    dirname: jest.fn((path: string) => {
      const normalized = path.replace(/\/$/, '');
      const lastSlash = normalized.lastIndexOf('/');
      if (lastSlash <= 0) {
        return '/';
      }
      return normalized.substring(0, lastSlash) || '/';
    }),
    exists: jest.fn(),
    createDirectory: jest.fn(),
    writeFile: jest.fn(),
    readFile: jest.fn(),
  },
}));

jest.mock('../../src/services/SettingsStorage', () => ({
  SettingsStorage: {
    getDailyNotesEnabled: jest.fn(),
    getDailyNotesFolder: jest.fn(),
    getDailyNotesTemplate: jest.fn(),
  },
}));

const mockedFileSystemService = FileSystemService as jest.Mocked<typeof FileSystemService>;
const mockedSettingsStorage = SettingsStorage as jest.Mocked<typeof SettingsStorage>;

describe('DailyNoteService', () => {
  const mockDate = new Date('2026-03-12T09:45:00');
  const vaultPath = 'file:///documents/vault';

  beforeEach(() => {
    jest.clearAllMocks();
    // Reset singleton
    (DailyNoteService as any).instance = null;
    
    // Default settings mocks
    mockedSettingsStorage.getDailyNotesEnabled.mockResolvedValue(true);
    mockedSettingsStorage.getDailyNotesFolder.mockResolvedValue('daily');
    mockedSettingsStorage.getDailyNotesTemplate.mockResolvedValue('');
  });

  describe('getTodayNotePath', () => {
    it('should return path for today note with YYYY-MM-DD.md format', async () => {
      // Test will fail initially - DailyNoteService not implemented
      const result = await DailyNoteService.getTodayNotePath(vaultPath, mockDate);
      
      expect(result).toBe('file:///documents/vault/daily/2026-03-12.md');
    });

    it('should use custom folder name from settings', async () => {
      mockedSettingsStorage.getDailyNotesFolder.mockResolvedValue('journal');
      
      const result = await DailyNoteService.getTodayNotePath(vaultPath, mockDate);
      
      expect(result).toBe('file:///documents/vault/journal/2026-03-12.md');
    });

    it('should trim whitespace from folder name', async () => {
      mockedSettingsStorage.getDailyNotesFolder.mockResolvedValue('  daily  ');
      
      const result = await DailyNoteService.getTodayNotePath(vaultPath, mockDate);
      
      expect(result).toBe('file:///documents/vault/daily/2026-03-12.md');
    });
  });

  describe('openTodayNote', () => {
    it('should create daily folder if it does not exist', async () => {
      mockedFileSystemService.exists.mockResolvedValue(false);
      mockedFileSystemService.writeFile.mockResolvedValue(undefined);
      
      await DailyNoteService.openTodayNote(vaultPath, mockDate);
      
      expect(mockedFileSystemService.createDirectory).toHaveBeenCalledWith(
        'file:///documents/vault/daily',
        { recursive: true }
      );
    });

    it('should create note file with empty content when no template', async () => {
      mockedSettingsStorage.getDailyNotesTemplate.mockResolvedValue('');
      mockedFileSystemService.exists
        .mockResolvedValueOnce(false)  // folder doesn't exist
        .mockResolvedValueOnce(false);  // file doesn't exist
      mockedFileSystemService.writeFile.mockResolvedValue(undefined);
      
      const result = await DailyNoteService.openTodayNote(vaultPath, mockDate);
      
      expect(mockedFileSystemService.writeFile).toHaveBeenCalledWith(
        'file:///documents/vault/daily/2026-03-12.md',
        ''
      );
      expect(result.notePath).toBe('file:///documents/vault/daily/2026-03-12.md');
      expect(result.created).toBe(true);
    });

    it('should not recreate existing note', async () => {
      mockedSettingsStorage.getDailyNotesTemplate.mockResolvedValue('');
      mockedFileSystemService.exists
        .mockResolvedValueOnce(true)   // folder exists
        .mockResolvedValueOnce(true);  // file exists
      
      const result = await DailyNoteService.openTodayNote(vaultPath, mockDate);
      
      expect(mockedFileSystemService.writeFile).not.toHaveBeenCalled();
      expect(result.notePath).toBe('file:///documents/vault/daily/2026-03-12.md');
      expect(result.created).toBe(false);
    });

    it('should apply template variables when template exists', async () => {
      mockedSettingsStorage.getDailyNotesTemplate.mockResolvedValue('daily.md');
      mockedFileSystemService.exists
        .mockResolvedValueOnce(true)   // folder exists
        .mockResolvedValueOnce(false)  // file doesn't exist
        .mockResolvedValueOnce(true)   // templates directory exists
        .mockResolvedValueOnce(true);  // template file exists
      mockedFileSystemService.readFile.mockResolvedValue('# {{year}}-{{month}}-{{day}}\nTime: {{hour}}:{{minute}} {{ampm}}');
      mockedFileSystemService.writeFile.mockResolvedValue(undefined);
      
      const result = await DailyNoteService.openTodayNote(vaultPath, mockDate);
      
      expect(mockedFileSystemService.writeFile).toHaveBeenCalledWith(
        'file:///documents/vault/daily/2026-03-12.md',
        '# 2026-03-12\nTime: 09:45 AM'
      );
    });

    it('should strip {{cursor}} variable from template', async () => {
      mockedSettingsStorage.getDailyNotesTemplate.mockResolvedValue('daily.md');
      mockedFileSystemService.exists
        .mockResolvedValueOnce(true)   // folder exists
        .mockResolvedValueOnce(false)  // file doesn't exist
        .mockResolvedValueOnce(true)   // templates directory exists
        .mockResolvedValueOnce(true);  // template file exists
      mockedFileSystemService.readFile.mockResolvedValue('# Today\n{{cursor}}\nSome text');
      mockedFileSystemService.writeFile.mockResolvedValue(undefined);
      
      const result = await DailyNoteService.openTodayNote(vaultPath, mockDate);
      
      const writtenContent = mockedFileSystemService.writeFile.mock.calls[0][1];
      expect(writtenContent).not.toContain('{{cursor}}');
      expect(writtenContent).toContain('# Today');
      expect(writtenContent).toContain('Some text');
    });
  });

  describe('applyTemplateVariables', () => {
    it('should replace year, month, day variables', async () => {
      const template = 'Date: {{year}}/{{month}}/{{day}}';
      
      const result = await (DailyNoteService as any).applyTemplateVariables(template, mockDate);
      
      expect(result.content).toBe('Date: 2026/03/12');
    });

    it('should replace hour, minute, ampm variables', async () => {
      const template = 'Time: {{hour}}:{{minute}} {{ampm}}';
      
      const result = await (DailyNoteService as any).applyTemplateVariables(template, mockDate);
      
      expect(result.content).toBe('Time: 09:45 AM');
    });

    it('should return cursor position when {{cursor}} present', async () => {
      const template = 'Header\n{{cursor}}\nFooter';
      
      const result = await (DailyNoteService as any).applyTemplateVariables(template, mockDate);
      
      expect(result.content).toBe('Header\n\nFooter');
      expect(result.cursorPosition).toBe(7); // After "Header\n"
    });

    it('should handle AM/PM correctly', async () => {
      const pmDate = new Date('2026-03-12T14:30:00');
      const template = '{{ampm}}';
      
      const result = await (DailyNoteService as any).applyTemplateVariables(template, pmDate);
      
      expect(result.content).toBe('PM');
    });
  });

  describe('generateDateFilename', () => {
    it('should generate YYYY-MM-DD.md format', async () => {
      const result = await (DailyNoteService as any).generateDateFilename(mockDate);
      
      expect(result).toBe('2026-03-12.md');
    });

    it('should zero-pad month and day', async () => {
      const janDate = new Date('2026-01-05T10:00:00');
      const result = await (DailyNoteService as any).generateDateFilename(janDate);
      
      expect(result).toBe('2026-01-05.md');
    });
  });
});
