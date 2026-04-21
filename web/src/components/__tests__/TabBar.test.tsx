import { describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { TabBar } from '../TabBar'
import type { Tab } from '../../lib/tabs'

const tabs: Tab[] = [
  { id: 'a', path: 'notes/alpha.md' },
  { id: 'b', path: 'notes/beta.md' },
]

describe('<TabBar />', () => {
  it('renders nothing when tabs are empty', () => {
    const { container } = render(
      <TabBar
        tabs={[]}
        activeId={null}
        dirtyIds={new Set()}
        onActivate={vi.fn()}
        onClose={vi.fn()}
      />,
    )
    expect(container.firstChild).toBeNull()
  })

  it('renders each tab by basename', () => {
    render(
      <TabBar
        tabs={tabs}
        activeId="a"
        dirtyIds={new Set()}
        onActivate={vi.fn()}
        onClose={vi.fn()}
      />,
    )
    expect(screen.getByText('alpha.md')).toBeInTheDocument()
    expect(screen.getByText('beta.md')).toBeInTheDocument()
  })

  it('marks dirty tabs with a bullet', () => {
    render(
      <TabBar
        tabs={tabs}
        activeId="a"
        dirtyIds={new Set(['b'])}
        onActivate={vi.fn()}
        onClose={vi.fn()}
      />,
    )
    expect(screen.getByText('beta.md •')).toBeInTheDocument()
    expect(screen.getByText('alpha.md')).toBeInTheDocument()
  })

  it('fires onActivate when a tab is clicked', async () => {
    const user = userEvent.setup()
    const onActivate = vi.fn()
    render(
      <TabBar
        tabs={tabs}
        activeId="a"
        dirtyIds={new Set()}
        onActivate={onActivate}
        onClose={vi.fn()}
      />,
    )
    await user.click(screen.getByText('beta.md'))
    expect(onActivate).toHaveBeenCalledWith('b')
  })

  it('fires onClose when the X is clicked, not onActivate', async () => {
    const user = userEvent.setup()
    const onActivate = vi.fn()
    const onClose = vi.fn()
    render(
      <TabBar
        tabs={tabs}
        activeId="a"
        dirtyIds={new Set()}
        onActivate={onActivate}
        onClose={onClose}
      />,
    )
    const [closeA] = screen.getAllByRole('button', { name: /close tab/i })
    await user.click(closeA)
    expect(onClose).toHaveBeenCalledWith('a')
    expect(onActivate).not.toHaveBeenCalled()
  })

  it('middle-click closes the tab', () => {
    const onClose = vi.fn()
    render(
      <TabBar
        tabs={tabs}
        activeId="a"
        dirtyIds={new Set()}
        onActivate={vi.fn()}
        onClose={onClose}
      />,
    )
    const row = screen.getByText('alpha.md').closest('div')!
    const ev = new MouseEvent('auxclick', { button: 1, bubbles: true, cancelable: true })
    fireEvent(row, ev)
    expect(onClose).toHaveBeenCalledWith('a')
  })
})
