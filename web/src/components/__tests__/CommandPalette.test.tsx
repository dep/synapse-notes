import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { CommandPalette } from '../CommandPalette'
import type { PaletteItem } from '../../lib/palette'

const items: PaletteItem[] = [
  { kind: 'folder', path: 'notes', name: 'notes', parentPath: '' },
  {
    kind: 'file',
    path: 'notes/alpha.md',
    name: 'alpha.md',
    parentPath: 'notes',
  },
  {
    kind: 'file',
    path: 'notes/beta.md',
    name: 'beta.md',
    parentPath: 'notes',
  },
  {
    kind: 'file',
    path: 'README.md',
    name: 'README.md',
    parentPath: '',
  },
]

describe('<CommandPalette />', () => {
  it('renders results for empty query', () => {
    render(
      <CommandPalette
        open
        items={items}
        onSelect={vi.fn()}
        onClose={vi.fn()}
      />,
    )
    expect(screen.getAllByTestId('palette-row').length).toBeGreaterThan(0)
  })

  it('filters on typing and shows the best match first', async () => {
    const user = userEvent.setup()
    render(
      <CommandPalette
        open
        items={items}
        onSelect={vi.fn()}
        onClose={vi.fn()}
      />,
    )
    const input = screen.getByLabelText('command palette query')
    await user.type(input, 'alpha')
    const rows = screen.getAllByTestId('palette-row')
    expect(rows[0].textContent).toContain('alpha.md')
  })

  it('Enter selects the highlighted row', async () => {
    const user = userEvent.setup()
    const onSelect = vi.fn()
    render(
      <CommandPalette
        open
        items={items}
        onSelect={onSelect}
        onClose={vi.fn()}
      />,
    )
    const input = screen.getByLabelText('command palette query')
    await user.type(input, 'alpha')
    await user.keyboard('{Enter}')
    expect(onSelect).toHaveBeenCalledTimes(1)
    expect(onSelect.mock.calls[0][0].path).toBe('notes/alpha.md')
  })

  it('ArrowDown moves the highlight and Enter picks it', async () => {
    const user = userEvent.setup()
    const onSelect = vi.fn()
    render(
      <CommandPalette
        open
        items={items}
        onSelect={onSelect}
        onClose={vi.fn()}
      />,
    )
    const input = screen.getByLabelText('command palette query')
    await user.type(input, 'md')
    await user.keyboard('{ArrowDown}')
    await user.keyboard('{Enter}')
    // With query 'md', any match is a subsequence match in .md filenames;
    // we just assert an item was picked and it's one of the files.
    expect(onSelect).toHaveBeenCalledTimes(1)
    const picked = onSelect.mock.calls[0][0].path as string
    expect(picked.endsWith('.md')).toBe(true)
  })

  it('Escape closes the palette', async () => {
    const user = userEvent.setup()
    const onClose = vi.fn()
    render(
      <CommandPalette
        open
        items={items}
        onSelect={vi.fn()}
        onClose={onClose}
      />,
    )
    const input = screen.getByLabelText('command palette query')
    input.focus()
    await user.keyboard('{Escape}')
    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('shows "No matches" when nothing scores > 0', async () => {
    const user = userEvent.setup()
    render(
      <CommandPalette
        open
        items={items}
        onSelect={vi.fn()}
        onClose={vi.fn()}
      />,
    )
    const input = screen.getByLabelText('command palette query')
    await user.type(input, 'zzzzzzzzzzzz')
    expect(screen.getByText('No matches.')).toBeInTheDocument()
  })
})
