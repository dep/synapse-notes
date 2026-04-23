import type { ReactNode } from 'react'
import FolderIcon from '@mui/icons-material/Folder'
import CalendarMonthIcon from '@mui/icons-material/CalendarMonth'
import EditIcon from '@mui/icons-material/Edit'
import GroupIcon from '@mui/icons-material/Group'
import WorkIcon from '@mui/icons-material/Work'
import Inventory2Icon from '@mui/icons-material/Inventory2'
import MenuBookIcon from '@mui/icons-material/MenuBook'
import DraftsIcon from '@mui/icons-material/Drafts'
import LightbulbIcon from '@mui/icons-material/Lightbulb'
import InboxIcon from '@mui/icons-material/Inbox'
import TaskAltIcon from '@mui/icons-material/TaskAlt'
import StarIcon from '@mui/icons-material/Star'
import LabelIcon from '@mui/icons-material/Label'
import PhotoLibraryIcon from '@mui/icons-material/PhotoLibrary'
import CodeIcon from '@mui/icons-material/Code'
import ScienceIcon from '@mui/icons-material/Science'
import BuildIcon from '@mui/icons-material/Build'
import PublicIcon from '@mui/icons-material/Public'
import RestaurantIcon from '@mui/icons-material/Restaurant'
import FlightIcon from '@mui/icons-material/Flight'
import FitnessCenterIcon from '@mui/icons-material/FitnessCenter'
import SavingsIcon from '@mui/icons-material/Savings'
import SchoolIcon from '@mui/icons-material/School'
import DescriptionIcon from '@mui/icons-material/Description'
import ExtensionIcon from '@mui/icons-material/Extension'
import PersonIcon from '@mui/icons-material/Person'
import SettingsIcon from '@mui/icons-material/Settings'
import HistoryIcon from '@mui/icons-material/History'
import ArticleIcon from '@mui/icons-material/Article'
import SmartToyIcon from '@mui/icons-material/SmartToy'
import PhoneIphoneIcon from '@mui/icons-material/PhoneIphone'
import TvIcon from '@mui/icons-material/Tv'
import LanguageIcon from '@mui/icons-material/Language'
import SummarizeIcon from '@mui/icons-material/Summarize'
import FolderCopyIcon from '@mui/icons-material/FolderCopy'
import type { FolderIconKey, FolderStyle } from '../lib/folderStyle'

const ICON_MAP: Record<FolderIconKey, typeof FolderIcon> = {
  folder: FolderIcon,
  calendar: CalendarMonthIcon,
  edit: EditIcon,
  group: GroupIcon,
  work: WorkIcon,
  archive: Inventory2Icon,
  book: ArticleIcon,
  menu_book: MenuBookIcon,
  draft: DraftsIcon,
  idea: LightbulbIcon,
  inbox: InboxIcon,
  task: TaskAltIcon,
  star: StarIcon,
  label: LabelIcon,
  photo: PhotoLibraryIcon,
  code: CodeIcon,
  science: ScienceIcon,
  build: BuildIcon,
  public: PublicIcon,
  restaurant: RestaurantIcon,
  flight: FlightIcon,
  fitness: FitnessCenterIcon,
  piggy: SavingsIcon,
  school: SchoolIcon,
  description: DescriptionIcon,
  extension: ExtensionIcon,
  person: PersonIcon,
  settings: SettingsIcon,
  history: HistoryIcon,
  robot: SmartToyIcon,
  phone: PhoneIphoneIcon,
  tv: TvIcon,
  web: LanguageIcon,
  summary: SummarizeIcon,
  files: FolderCopyIcon,
}

export function StyledFolderIcon({ style }: { style: FolderStyle }): ReactNode {
  if (style.emoji) {
    return (
      <span
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 18,
          width: 20,
          height: 20,
          lineHeight: 1,
        }}
        aria-hidden
      >
        {style.emoji}
      </span>
    )
  }
  const Icon = ICON_MAP[style.icon] ?? FolderIcon
  return <Icon fontSize="small" sx={{ color: style.color }} />
}
