import { convertHtmlToMarkdown } from '../../src/utils/htmlToMarkdown';

describe('convertHtmlToMarkdown', () => {
  describe('basic text conversion', () => {
    it('returns plain text as-is', () => {
      const plainText = 'Just some plain text';
      expect(convertHtmlToMarkdown(plainText)).toBe('Just some plain text');
    });

    it('converts HTML paragraph to plain text', () => {
      const html = '<p>This is a paragraph</p>';
      expect(convertHtmlToMarkdown(html)).toBe('This is a paragraph');
    });
  });

  describe('headings conversion', () => {
    it('converts h1 to markdown heading', () => {
      const html = '<h1>Heading 1</h1>';
      expect(convertHtmlToMarkdown(html)).toBe('# Heading 1');
    });

    it('converts h2 to markdown heading', () => {
      const html = '<h2>Heading 2</h2>';
      expect(convertHtmlToMarkdown(html)).toBe('## Heading 2');
    });

    it('converts h3 to markdown heading', () => {
      const html = '<h3>Heading 3</h3>';
      expect(convertHtmlToMarkdown(html)).toBe('### Heading 3');
    });

    it('converts h4 to markdown heading', () => {
      const html = '<h4>Heading 4</h4>';
      expect(convertHtmlToMarkdown(html)).toBe('#### Heading 4');
    });

    it('converts h5 to markdown heading', () => {
      const html = '<h5>Heading 5</h5>';
      expect(convertHtmlToMarkdown(html)).toBe('##### Heading 5');
    });

    it('converts h6 to markdown heading', () => {
      const html = '<h6>Heading 6</h6>';
      expect(convertHtmlToMarkdown(html)).toBe('###### Heading 6');
    });
  });

  describe('text formatting', () => {
    it('converts strong to bold markdown', () => {
      const html = '<strong>bold text</strong>';
      expect(convertHtmlToMarkdown(html)).toBe('**bold text**');
    });

    it('converts b to bold markdown', () => {
      const html = '<b>bold text</b>';
      expect(convertHtmlToMarkdown(html)).toBe('**bold text**');
    });

    it('converts em to italic markdown', () => {
      const html = '<em>italic text</em>';
      expect(convertHtmlToMarkdown(html)).toBe('_italic text_');
    });

    it('converts i to italic markdown', () => {
      const html = '<i>italic text</i>';
      expect(convertHtmlToMarkdown(html)).toBe('_italic text_');
    });
  });

  describe('links conversion', () => {
    it('converts anchor tag to markdown link', () => {
      const html = '<a href="https://example.com">Example</a>';
      expect(convertHtmlToMarkdown(html)).toBe('[Example](https://example.com)');
    });

    it('converts link with title attribute', () => {
      const html = '<a href="https://example.com" title="Example Site">Example</a>';
      expect(convertHtmlToMarkdown(html)).toBe('[Example](https://example.com "Example Site")');
    });
  });

  describe('images conversion', () => {
    it('converts img tag to markdown image', () => {
      const html = '<img src="image.png" alt="Description">';
      expect(convertHtmlToMarkdown(html)).toBe('![Description](image.png)');
    });

    it('converts img tag without alt text', () => {
      const html = '<img src="image.png">';
      expect(convertHtmlToMarkdown(html)).toBe('![](image.png)');
    });
  });

  describe('lists conversion', () => {
    it('converts unordered list to markdown', () => {
      const html = '<ul><li>Item 1</li><li>Item 2</li><li>Item 3</li></ul>';
      expect(convertHtmlToMarkdown(html)).toBe('-   Item 1\n-   Item 2\n-   Item 3');
    });

    it('converts ordered list to markdown', () => {
      const html = '<ol><li>First</li><li>Second</li><li>Third</li></ol>';
      expect(convertHtmlToMarkdown(html)).toBe('1.  First\n2.  Second\n3.  Third');
    });

    it('converts nested unordered lists', () => {
      const html = '<ul><li>Item 1<ul><li>Nested 1</li><li>Nested 2</li></ul></li><li>Item 2</li></ul>';
      expect(convertHtmlToMarkdown(html)).toBe('-   Item 1\n    -   Nested 1\n    -   Nested 2\n-   Item 2');
    });
  });

  describe('blockquotes conversion', () => {
    it('converts blockquote to markdown', () => {
      const html = '<blockquote>This is a quote</blockquote>';
      expect(convertHtmlToMarkdown(html)).toBe('> This is a quote');
    });

    it('converts blockquote with multiple paragraphs', () => {
      const html = '<blockquote><p>First paragraph</p><p>Second paragraph</p></blockquote>';
      expect(convertHtmlToMarkdown(html)).toBe('> First paragraph\n> \n> Second paragraph');
    });
  });

  describe('code conversion', () => {
    it('converts inline code to markdown', () => {
      const html = '<code>inline code</code>';
      expect(convertHtmlToMarkdown(html)).toBe('`inline code`');
    });

    it('converts pre/code block to fenced code block', () => {
      const html = '<pre><code>const x = 1;\nconsole.log(x);</code></pre>';
      expect(convertHtmlToMarkdown(html)).toBe('```\nconst x = 1;\nconsole.log(x);\n```');
    });

    it('converts pre block with language class', () => {
      const html = '<pre><code class="language-javascript">const x = 1;</code></pre>';
      expect(convertHtmlToMarkdown(html)).toBe('```javascript\nconst x = 1;\n```');
    });
  });

  describe('unsupported elements handling', () => {
    it('strips div but preserves content', () => {
      const html = '<div>Content inside div</div>';
      expect(convertHtmlToMarkdown(html)).toBe('Content inside div');
    });

    it('strips span but preserves content', () => {
      const html = '<span>Content inside span</span>';
      expect(convertHtmlToMarkdown(html)).toBe('Content inside span');
    });

    it('strips inline styles but preserves text', () => {
      const html = '<p style="color: red;">Styled text</p>';
      expect(convertHtmlToMarkdown(html)).toBe('Styled text');
    });

    it('handles complex nested unsupported elements', () => {
      const html = '<div><span>Text in </span><strong>nested</strong> elements</div>';
      expect(convertHtmlToMarkdown(html)).toBe('Text in **nested** elements');
    });
  });

  describe('complex HTML documents', () => {
    it('converts full HTML document with mixed content', () => {
      const html = `
        <h1>Title</h1>
        <p>This is a paragraph with <strong>bold</strong> and <em>italic</em> text.</p>
        <ul>
          <li>Item 1</li>
          <li>Item 2 with <a href="https://example.com">link</a></li>
        </ul>
        <blockquote>
          <p>A quoted paragraph</p>
        </blockquote>
      `;
      const expected = `# Title

This is a paragraph with **bold** and _italic_ text.

-   Item 1
-   Item 2 with [link](https://example.com)

> A quoted paragraph`;
      expect(convertHtmlToMarkdown(html)).toBe(expected);
    });

    it('handles HTML from rich text editors', () => {
      const html = '<div><p>Hello <b>world</b></p><ul><li>Point 1</li><li>Point 2</li></ul></div>';
      const expected = `Hello **world**

-   Point 1
-   Point 2`;
      expect(convertHtmlToMarkdown(html)).toBe(expected);
    });
  });

  describe('edge cases', () => {
    it('handles empty string', () => {
      expect(convertHtmlToMarkdown('')).toBe('');
    });

    it('handles whitespace-only input', () => {
      expect(convertHtmlToMarkdown('   \n\t  ')).toBe('');
    });

    it('handles HTML with extra whitespace', () => {
      const html = '<p>  Text with spaces  </p>';
      expect(convertHtmlToMarkdown(html)).toBe('Text with spaces');
    });

    it('handles HTML entities', () => {
      const html = '<p>Text with &lt;entities&gt; and &amp; symbols</p>';
      expect(convertHtmlToMarkdown(html)).toBe('Text with <entities> and & symbols');
    });

    it('preserves plain text when no HTML tags present', () => {
      const text = 'Just regular text without any HTML';
      expect(convertHtmlToMarkdown(text)).toBe('Just regular text without any HTML');
    });
  });
});
