export const DAILY_NOTES_FOLDER = 'Daily Notes'

function pad(n: number): string {
  return n < 10 ? `0${n}` : String(n)
}

export function formatLocalDate(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

export function dailyNotePath(d: Date = new Date()): string {
  return `${DAILY_NOTES_FOLDER}/${formatLocalDate(d)}.md`
}
