import TurndownService from 'turndown';

const turndownService = new TurndownService({
  headingStyle: 'atx',
  bulletListMarker: '-',
  codeBlockStyle: 'fenced',
  emDelimiter: '_',
  strongDelimiter: '**',
});

// Custom rules for better handling
turndownService.addRule('strikethrough', {
  filter: ['del', 's'],
  replacement: (content) => `~~${content}~~`,
});

// Keep line breaks in paragraphs
turndownService.addRule('paragraph', {
  filter: 'p',
  replacement: (content) => {
    const trimmed = content.trim();
    if (!trimmed) return '';
    return `\n\n${trimmed}\n\n`;
  },
});

export function convertHtmlToMarkdown(html: string): string {
  if (!html || !html.trim()) {
    return '';
  }

  // Check if the content actually contains HTML tags
  const hasHtmlTags = /<[a-z][\s\S]*>/i.test(html);

  if (!hasHtmlTags) {
    // No HTML tags found, return as-is
    return html.trim();
  }

  // Clean up extra whitespace before conversion
  const cleanedHtml = html
    .replace(/>\s+</g, '><')  // Remove whitespace between tags
    .trim();

  const markdown = turndownService.turndown(cleanedHtml);

  // Clean up extra whitespace after conversion
  return markdown
    .replace(/\n{3,}/g, '\n\n')  // Max 2 consecutive newlines
    .trim();
}
