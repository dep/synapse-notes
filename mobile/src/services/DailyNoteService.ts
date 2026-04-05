import { FileSystemService } from './FileSystemService';
import { SettingsStorage } from './SettingsStorage';
import { TemplateStorage } from './TemplateStorage';

export interface DailyNoteResult {
  notePath: string;
  created: boolean;
  cursorPosition?: number;
}

interface TemplateResult {
  content: string;
  cursorPosition?: number;
}

export class DailyNoteService {
  private static instance: DailyNoteService | null = null;

  private constructor() {}

  static getInstance(): DailyNoteService {
    if (!DailyNoteService.instance) {
      DailyNoteService.instance = new DailyNoteService();
    }
    return DailyNoteService.instance;
  }

  static clearInstance(): void {
    DailyNoteService.instance = null;
  }

  // Generate today's note path based on settings
  static async getTodayNotePath(vaultPath: string, date: Date = new Date()): Promise<string> {
    const folderName = (await SettingsStorage.getDailyNotesFolder()).trim();
    const dailyFolder = folderName || 'daily';
    const fileName = this.generateDateFilename(date);
    return FileSystemService.join(vaultPath, dailyFolder, fileName);
  }

  // Generate date-based filename: YYYY-MM-DD.md
  private static generateDateFilename(date: Date): string {
    const year = date.getFullYear().toString().padStart(4, '0');
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}.md`;
  }

  // Open or create today's note
  static async openTodayNote(vaultPath: string, date: Date = new Date()): Promise<DailyNoteResult> {
    const notePath = await this.getTodayNotePath(vaultPath, date);
    const folderPath = FileSystemService.dirname(notePath);
    
    // Ensure daily folder exists
    const folderExists = await FileSystemService.exists(folderPath);
    if (!folderExists) {
      await FileSystemService.createDirectory(folderPath, { recursive: true });
    }

    // Check if note already exists
    const fileExists = await FileSystemService.exists(notePath);
    
    let cursorPosition: number | undefined;
    
    if (!fileExists) {
      // Create new note with template if specified
      let content = '';
      const templateName = (await SettingsStorage.getDailyNotesTemplate()).trim();
      
      if (templateName) {
          const templatesDir = await this.getTemplatesDirectory(vaultPath);
          if (templatesDir) {
            const templatePath = FileSystemService.join(templatesDir, templateName);
            const templateExists = await FileSystemService.exists(templatePath);
            
            if (templateExists) {
              const templateContent = await FileSystemService.readFile(templatePath) as string;
              const result = TemplateStorage.applyTemplateVariables(templateContent, date);
              content = result.content;
              cursorPosition = result.cursorPosition ?? undefined;
            }
          }
        }
      
      await FileSystemService.writeFile(notePath, content);
      
      return {
        notePath,
        created: true,
        cursorPosition,
      };
    }

    return {
      notePath,
      created: false,
    };
  }

  // Get templates directory path
  private static async getTemplatesDirectory(vaultPath: string): Promise<string | null> {
    const templatesPath = await TemplateStorage.getTemplatesDirectoryPath(vaultPath);
    const exists = await FileSystemService.exists(templatesPath);
    return exists ? templatesPath : null;
  }

  // Apply template variable substitution
  private static applyTemplateVariables(template: string, date: Date): TemplateResult {
    const year = date.getFullYear().toString().padStart(4, '0');
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    
    let hour = date.getHours();
    const ampm = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    hour = hour === 0 ? 12 : hour;
    const hourStr = hour.toString().padStart(2, '0');
    const minute = date.getMinutes().toString().padStart(2, '0');

    let cursorPosition: number | undefined;
    
    // Find cursor position if {{cursor}} is present
    const cursorIndex = template.indexOf('{{cursor}}');
    if (cursorIndex !== -1) {
      cursorPosition = cursorIndex;
    }

    // Replace variables
    let content = template
      .replace(/\{\{year\}\}/g, year)
      .replace(/\{\{month\}\}/g, month)
      .replace(/\{\{day\}\}/g, day)
      .replace(/\{\{hour\}\}/g, hourStr)
      .replace(/\{\{minute\}\}/g, minute)
      .replace(/\{\{ampm\}\}/g, ampm)
      .replace(/\{\{cursor\}\}/g, '');

    // Adjust cursor position after variable replacement (simplified)
    if (cursorPosition !== undefined) {
      // Count how many characters before cursor were replaced
      const beforeCursor = template.substring(0, cursorIndex);
      const replacements = beforeCursor.match(/\{\{(year|month|day|hour|minute|ampm|cursor)\}\}/g);
      if (replacements) {
        // Each replacement removes 2+4=6 to 2+8=10 chars and adds 2-4 chars
        // This is a simplified calculation
        let offset = 0;
        for (const match of replacements) {
          switch (match) {
            case '{{year}}': offset -= 6; offset += 4; break;
            case '{{month}}': offset -= 8; offset += 2; break;
            case '{{day}}': offset -= 6; offset += 2; break;
            case '{{hour}}': offset -= 8; offset += 2; break;
            case '{{minute}}': offset -= 10; offset += 2; break;
            case '{{ampm}}': offset -= 8; offset += 2; break;
            case '{{cursor}}': offset -= 10; break;
          }
        }
        cursorPosition += offset;
      }
    }

    return { content, cursorPosition };
  }

}
