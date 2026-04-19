import { describe, expect, it } from 'vitest'
import { renderToString } from 'react-dom/server'
import App from './App'

describe('App', () => {
  it('renders the Synapse shell title', () => {
    const html = renderToString(<App />)
    expect(html).toContain('Synapse')
    expect(html).toContain('Web (MVP)')
  })
})
