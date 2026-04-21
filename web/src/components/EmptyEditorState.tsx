import { Box, Paper, Stack, Typography } from '@mui/material'
import CalendarMonthIcon from '@mui/icons-material/CalendarMonth'
import KeyboardCommandKeyIcon from '@mui/icons-material/KeyboardCommandKey'
import MenuIcon from '@mui/icons-material/Menu'

export function EmptyEditorState({
  mobile,
  todayLabel,
  onOpenToday,
  onOpenPalette,
  onOpenSidebar,
}: {
  mobile: boolean
  todayLabel: string
  onOpenToday: () => void
  onOpenPalette: () => void
  onOpenSidebar: () => void
}) {
  return (
    <Box
      sx={{
        height: '100%',
        width: '100%',
        overflow: 'auto',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        p: 3,
      }}
    >
      <Box sx={{ width: '100%', maxWidth: 520 }}>
        <Stack spacing={0.5} sx={{ mb: 4 }} alignItems="center">
          <Typography
            variant="overline"
            sx={{ color: 'text.disabled', letterSpacing: 2 }}
          >
            Synapse Web
          </Typography>
          <Typography variant="h6" sx={{ fontWeight: 600 }}>
            Nothing open.
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Pick a file, or start with one of these.
          </Typography>
        </Stack>

        <Stack spacing={1.5}>
          <ActionCard
            icon={<CalendarMonthIcon sx={{ color: '#6EA8FE' }} />}
            title="Open today's note"
            subtitle={todayLabel}
            shortcut="⌃⌘H"
            onClick={onOpenToday}
          />
          <ActionCard
            icon={<KeyboardCommandKeyIcon sx={{ color: '#9B8CFF' }} />}
            title="Quick find"
            subtitle="Jump to a file or folder"
            shortcut="⌘K"
            onClick={onOpenPalette}
          />
          {mobile && (
            <ActionCard
              icon={<MenuIcon sx={{ color: '#7DDE92' }} />}
              title="Browse files"
              subtitle="Open the sidebar"
              onClick={onOpenSidebar}
            />
          )}
        </Stack>

        <Box sx={{ mt: 4 }}>
          <Typography
            variant="caption"
            color="text.disabled"
            sx={{ display: 'block', textAlign: 'center' }}
          >
            ⌘S save · ⌘K find · ⌃⌘H today · ⌃P toggle preview · ⌃W close tab
          </Typography>
        </Box>
      </Box>
    </Box>
  )
}

function ActionCard({
  icon,
  title,
  subtitle,
  shortcut,
  onClick,
}: {
  icon: React.ReactNode
  title: string
  subtitle: string
  shortcut?: string
  onClick: () => void
}) {
  return (
    <Paper
      elevation={0}
      onClick={onClick}
      sx={{
        display: 'flex',
        alignItems: 'center',
        gap: 1.5,
        p: 1.5,
        cursor: 'pointer',
        border: '1px solid',
        borderColor: 'divider',
        bgcolor: 'transparent',
        transition: 'background-color 120ms, border-color 120ms',
        '&:hover': {
          bgcolor: 'action.hover',
          borderColor: 'primary.main',
        },
      }}
    >
      <Box
        sx={{
          width: 32,
          height: 32,
          borderRadius: 1,
          display: 'grid',
          placeItems: 'center',
          bgcolor: 'action.hover',
          flexShrink: 0,
        }}
      >
        {icon}
      </Box>
      <Box sx={{ flex: 1, minWidth: 0 }}>
        <Typography
          variant="body2"
          sx={{ fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}
        >
          {title}
        </Typography>
        <Typography
          variant="caption"
          color="text.secondary"
          sx={{
            display: 'block',
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
          }}
        >
          {subtitle}
        </Typography>
      </Box>
      {shortcut && (
        <Typography
          variant="caption"
          sx={{
            fontFamily: 'ui-monospace, Menlo, monospace',
            color: 'text.disabled',
            px: 0.75,
            py: 0.25,
            borderRadius: 0.5,
            border: '1px solid',
            borderColor: 'divider',
            fontSize: 11,
            flexShrink: 0,
          }}
        >
          {shortcut}
        </Typography>
      )}
    </Paper>
  )
}
