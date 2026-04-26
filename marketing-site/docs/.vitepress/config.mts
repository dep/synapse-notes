import { defineConfig } from 'vitepress'

export default defineConfig({
  title: "Synapse Notes",
  description: "Markdown-based knowledge management app for macOS.",
  appearance: 'force-dark', // Always use dark mode to match app aesthetic

  themeConfig: {
    nav: [
      { text: 'Guide', link: '/' },
      { text: 'Support', link: '/support' },
      {
        text: 'Legal',
        items: [
          { text: 'Privacy Policy', link: '/privacy-policy' },
          { text: 'Terms of Service', link: '/terms-of-service' }
        ]
      }
    ],

    // Enable the sidebar and configure it
    sidebar: [
      {
        text: 'Synapse Notes User Guide',
        items: [
          { text: 'Setup & Installation', link: '/#setup-installation' },
          { text: 'Initial Configuration', link: '/#initial-configuration' },
          { text: 'Features', link: '/#features' },
          { text: 'Settings', link: '/#settings' },
          { text: 'Keyboard Shortcuts', link: '/#keyboard-shortcuts' },
          { text: 'Context-Aware Assistance', link: '/#context-aware-assistance' },
          { text: 'Support the Developer', link: '/#support-the-developer' },
          { text: 'Additional Documentation', link: '/#additional-documentation' }
        ]
      },
      {
        text: 'Documentation',
        items: [
          { text: 'Markdown Guide', link: '/markdown' }
        ]
      },
      {
        text: 'Legal & support',
        items: [
          { text: 'Support', link: '/support' },
          { text: 'Privacy Policy', link: '/privacy-policy' },
          { text: 'Terms of Service', link: '/terms-of-service' }
        ]
      }
    ],

    outline: {
      level: [2, 3],
      label: 'On This Page'
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/dep/synapse' }
    ],

    search: {
      provider: 'local'
    }
  },

  head: [
    ['meta', { name: 'theme-color', content: '#0d0d0d' }],
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/synapse-logo.svg' }]
  ]
})
