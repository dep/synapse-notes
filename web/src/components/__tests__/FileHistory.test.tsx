import type { ComponentProps } from 'react'
import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ThemeProvider, createTheme } from '@mui/material'
import { FileHistory } from '../FileHistory'
import * as contents from '../../github/contents'

vi.mock('../../github/contents', async (importOriginal) => {
  const actual = await importOriginal<typeof contents>()
  return {
    ...actual,
    fetchFileCommits: vi.fn(),
    fetchFileAtCommit: vi.fn(),
  }
})

const theme = createTheme()

function renderHistory(props: Partial<ComponentProps<typeof FileHistory>> = {}) {
  return render(
    <ThemeProvider theme={theme}>
      <FileHistory
        open
        token="t"
        owner="o"
        repo="r"
        branch="main"
        filePath="notes/a.md"
        onApply={vi.fn()}
        onClose={vi.fn()}
        {...props}
      />
    </ThemeProvider>,
  )
}

describe('<FileHistory />', () => {
  beforeEach(() => {
    vi.mocked(contents.fetchFileCommits).mockResolvedValue({
      ok: true,
      commits: [
        { sha: 'sha-slow', message: 'slow', date: '', author: '' },
        { sha: 'sha-fast', message: 'fast', date: '', author: '' },
      ],
    })
  })

  it('ignores stale preview when a newer commit is selected (race)', async () => {
    const user = userEvent.setup()
    vi.mocked(contents.fetchFileAtCommit).mockImplementation((_t, _o, _r, _p, commitSha) => {
      if (commitSha === 'sha-slow') {
        return new Promise((resolve) => {
          setTimeout(
            () => resolve({ ok: true, content: 'stale', sha: 'x', encoding: 'utf-8' as const }),
            80,
          )
        })
      }
      return Promise.resolve({
        ok: true,
        content: 'fresh',
        sha: 'y',
        encoding: 'utf-8' as const,
      })
    })

    renderHistory()

    await waitFor(() => {
      expect(screen.getByText('slow')).toBeInTheDocument()
    })

    await user.click(screen.getByText('slow'))
    await user.click(screen.getByText('fast'))

    await waitFor(
      () => {
        expect(screen.getByText('fresh')).toBeInTheDocument()
      },
      { timeout: 3000 },
    )
    expect(screen.queryByText('stale')).not.toBeInTheDocument()
  })
})
