import { useEffect, useState } from 'react'
import { Box } from '@mui/material'
import { useAuth } from './auth/AuthContext'
import { REPO_SELECTION_LOCAL_KEY } from './auth/storageKeys'
import { SignIn } from './components/SignIn'
import { RepoPicker } from './components/RepoPicker'
import { RepoEditor } from './components/RepoEditor'

export type SelectedRepo = {
  fullName: string
  defaultBranch: string
}

function loadSelectedRepo(): SelectedRepo | null {
  const raw = localStorage.getItem(REPO_SELECTION_LOCAL_KEY)
  if (!raw) return null
  try {
    const parsed = JSON.parse(raw) as Partial<SelectedRepo>
    if (
      typeof parsed.fullName === 'string' &&
      typeof parsed.defaultBranch === 'string'
    ) {
      return { fullName: parsed.fullName, defaultBranch: parsed.defaultBranch }
    }
  } catch {
    // fall through
  }
  return null
}

export function App() {
  const { token } = useAuth()
  const [selected, setSelected] = useState<SelectedRepo | null>(() =>
    loadSelectedRepo(),
  )

  useEffect(() => {
    if (selected) {
      localStorage.setItem(REPO_SELECTION_LOCAL_KEY, JSON.stringify(selected))
    } else {
      localStorage.removeItem(REPO_SELECTION_LOCAL_KEY)
    }
  }, [selected])

  if (!token) {
    return (
      <Box sx={{ minHeight: '100vh', display: 'grid', placeItems: 'center' }}>
        <SignIn />
      </Box>
    )
  }

  if (!selected) {
    return (
      <Box sx={{ minHeight: '100vh' }}>
        <RepoPicker onSelect={setSelected} />
      </Box>
    )
  }

  return (
    <RepoEditor
      repo={selected}
      onChangeRepo={() => setSelected(null)}
    />
  )
}
