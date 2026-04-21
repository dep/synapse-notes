import { describe, expect, it, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Sidebar, type SidebarContextTarget } from '../Sidebar'
import type { TreeNode } from '../../github/tree'
import type { PinnedItem } from '../../lib/pins'
import type { SortSettings } from '../../lib/sort'

const buildTree = (): TreeNode => ({
  name: '',
  path: '',
  type: 'tree',
  children: [
    {
      name: 'notes',
      path: 'notes',
      type: 'tree',
      children: [
        { name: 'alpha.md', path: 'notes/alpha.md', type: 'blob', children: [] },
        { name: 'beta.md', path: 'notes/beta.md', type: 'blob', children: [] },
        {
          name: 'deep',
          path: 'notes/deep',
          type: 'tree',
          children: [
            { name: 'x.md', path: 'notes/deep/x.md', type: 'blob', children: [] },
          ],
        },
      ],
    },
    { name: 'README.md', path: 'README.md', type: 'blob', children: [] },
    { name: 'zeta.md', path: 'zeta.md', type: 'blob', children: [] },
  ],
})

const defaultProps = () => {
  const pinnedItems: PinnedItem[] = []
  const sort: SortSettings = { criterion: 'name', direction: 'asc' }
  return {
    root: buildTree(),
    activePath: null as string | null,
    pinnedItems,
    sort,
    currentFolder: '',
    onSortChange: vi.fn(),
    onNavigateFolder: vi.fn(),
    onSelectFile: vi.fn(),
    onContextMenu: vi.fn(),
    onPinnedClick: vi.fn(),
    onOpenToday: vi.fn(),
    todayLabel: '2026-04-21',
    todayPath: 'Daily Notes/2026-04-21.md',
  }
}

describe('<Sidebar /> drill-down', () => {
  it('renders only the root level initially', () => {
    render(<Sidebar {...defaultProps()} />)
    expect(screen.getByText('notes')).toBeInTheDocument()
    expect(screen.getByText('README.md')).toBeInTheDocument()
    expect(screen.getByText('zeta.md')).toBeInTheDocument()
    expect(screen.queryByText('alpha.md')).not.toBeInTheDocument()
    expect(screen.queryByText('beta.md')).not.toBeInTheDocument()
  })

  it('drills into a folder when clicked', async () => {
    const user = userEvent.setup()
    const props = defaultProps()
    render(<Sidebar {...props} />)
    await user.click(screen.getByText('notes'))
    expect(props.onNavigateFolder).toHaveBeenCalledWith('notes')
  })

  it('shows folder contents when currentFolder is set', () => {
    const props = { ...defaultProps(), currentFolder: 'notes' }
    render(<Sidebar {...props} />)
    expect(screen.getByText('alpha.md')).toBeInTheDocument()
    expect(screen.getByText('beta.md')).toBeInTheDocument()
    expect(screen.getByText('deep')).toBeInTheDocument()
    expect(screen.queryByText('README.md')).not.toBeInTheDocument()
  })

  it('opens files via onSelectFile (not drill) inside a folder', async () => {
    const user = userEvent.setup()
    const props = { ...defaultProps(), currentFolder: 'notes' }
    render(<Sidebar {...props} />)
    await user.click(screen.getByText('alpha.md'))
    expect(props.onSelectFile).toHaveBeenCalled()
    expect(props.onSelectFile.mock.calls[0][0]).toBe('notes/alpha.md')
    expect(props.onNavigateFolder).not.toHaveBeenCalled()
  })
})

describe('<Sidebar /> breadcrumb', () => {
  it('shows Root only at root with back disabled', () => {
    render(<Sidebar {...defaultProps()} />)
    expect(screen.getByRole('button', { name: /back/i })).toBeDisabled()
    expect(screen.getByText('Root')).toBeInTheDocument()
  })

  it('navigates back one level via back button', async () => {
    const user = userEvent.setup()
    const props = { ...defaultProps(), currentFolder: 'notes/deep' }
    render(<Sidebar {...props} />)
    const back = screen.getByRole('button', { name: /back/i })
    expect(back).toBeEnabled()
    await user.click(back)
    expect(props.onNavigateFolder).toHaveBeenCalledWith('notes')
  })

  it('navigates to a breadcrumb segment via click', async () => {
    const user = userEvent.setup()
    const props = { ...defaultProps(), currentFolder: 'notes/deep' }
    render(<Sidebar {...props} />)
    await user.click(screen.getByRole('button', { name: 'Root' }))
    expect(props.onNavigateFolder).toHaveBeenCalledWith('')
  })
})

describe('<Sidebar /> today row', () => {
  it('is always rendered above pinned + breadcrumb', () => {
    render(
      <Sidebar
        {...{
          ...defaultProps(),
          pinnedItems: [{ path: 'notes', kind: 'folder' as const }],
        }}
      />,
    )
    const today = screen.getByText('Today')
    const pinnedHeader = screen.getByText('Pinned')
    const rootSeg = screen.getByText('Root')
    expect(
      today.compareDocumentPosition(pinnedHeader) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy()
    expect(
      pinnedHeader.compareDocumentPosition(rootSeg) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy()
  })

  it('calls onOpenToday when clicked', async () => {
    const user = userEvent.setup()
    const props = defaultProps()
    render(<Sidebar {...props} />)
    await user.click(screen.getByText('Today'))
    expect(props.onOpenToday).toHaveBeenCalledTimes(1)
  })

  it('shows the date label', () => {
    const props = { ...defaultProps(), todayLabel: '2026-04-21' }
    render(<Sidebar {...props} />)
    expect(screen.getByText('2026-04-21')).toBeInTheDocument()
  })
})

describe('<Sidebar /> pinned', () => {
  it('renders pinned section above the sort controls and breadcrumb', () => {
    const props = {
      ...defaultProps(),
      pinnedItems: [{ path: 'notes', kind: 'folder' as const }],
    }
    const { container } = render(<Sidebar {...props} />)
    const pinnedHeader = screen.getByText('Pinned')
    const sortName = screen.getByText('Name')
    const rootSeg = screen.getByText('Root')
    expect(
      pinnedHeader.compareDocumentPosition(sortName) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy()
    expect(
      sortName.compareDocumentPosition(rootSeg) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy()
    expect(container).toBeInTheDocument()
  })

  it('drills into pinned folders via onPinnedClick', async () => {
    const user = userEvent.setup()
    const props = {
      ...defaultProps(),
      pinnedItems: [{ path: 'notes', kind: 'folder' as const }],
    }
    render(<Sidebar {...props} />)
    const [pinned] = screen.getAllByText('notes')
    await user.click(pinned)
    expect(props.onPinnedClick).toHaveBeenCalled()
    expect(props.onPinnedClick.mock.calls[0][0]).toEqual({
      path: 'notes',
      kind: 'folder',
    })
  })

  it('opens pinned files via onPinnedClick', async () => {
    const user = userEvent.setup()
    const props = {
      ...defaultProps(),
      pinnedItems: [{ path: 'notes/alpha.md', kind: 'file' as const }],
    }
    render(<Sidebar {...props} />)
    await user.click(screen.getByText('alpha.md'))
    expect(props.onPinnedClick).toHaveBeenCalled()
    expect(props.onPinnedClick.mock.calls[0][0]).toEqual({
      path: 'notes/alpha.md',
      kind: 'file',
    })
  })

  it('right-click on a pinned file opens the file context menu', () => {
    const props = {
      ...defaultProps(),
      pinnedItems: [{ path: 'notes/alpha.md', kind: 'file' as const }],
    }
    render(<Sidebar {...props} />)
    fireEvent.contextMenu(screen.getByText('alpha.md'))
    const [target] = props.onContextMenu.mock.calls[0] as [SidebarContextTarget]
    expect(target).toEqual({
      kind: 'file',
      path: 'notes/alpha.md',
      name: 'alpha.md',
    })
  })
})

describe('<Sidebar /> sort', () => {
  it('fires onSortChange when Date is clicked', async () => {
    const user = userEvent.setup()
    const props = defaultProps()
    render(<Sidebar {...props} />)
    await user.click(screen.getByText('Date'))
    expect(props.onSortChange).toHaveBeenCalledWith({
      criterion: 'date',
      direction: 'asc',
    })
  })

  it('flips direction when the active criterion is re-clicked', async () => {
    const user = userEvent.setup()
    const props = defaultProps()
    render(<Sidebar {...props} />)
    await user.click(screen.getByText('Name'))
    expect(props.onSortChange).toHaveBeenCalledWith({
      criterion: 'name',
      direction: 'desc',
    })
  })
})

describe('<Sidebar /> context menus', () => {
  it('fires onContextMenu with a file target on right-click', () => {
    const props = defaultProps()
    render(<Sidebar {...props} />)
    fireEvent.contextMenu(screen.getByText('README.md'))
    const [target] = props.onContextMenu.mock.calls[0] as [SidebarContextTarget]
    expect(target).toEqual({ kind: 'file', path: 'README.md', name: 'README.md' })
  })

  it('fires onContextMenu with a folder target on right-click', () => {
    const props = defaultProps()
    render(<Sidebar {...props} />)
    fireEvent.contextMenu(screen.getByText('notes'))
    const [target] = props.onContextMenu.mock.calls[0] as [SidebarContextTarget]
    expect(target).toEqual({ kind: 'folder', path: 'notes', name: 'notes' })
  })
})
