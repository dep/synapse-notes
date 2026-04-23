import { describe, expect, it } from 'vitest'
import {
  DAILY_NOTES_FOLDER,
  dailyNotePath,
  formatLocalDate,
} from '../dailyNote'

describe('formatLocalDate', () => {
  it('formats to YYYY-MM-DD with zero padding', () => {
    expect(formatLocalDate(new Date(2026, 0, 5))).toBe('2026-01-05')
    expect(formatLocalDate(new Date(2026, 11, 31))).toBe('2026-12-31')
  })
})

describe('dailyNotePath', () => {
  it('joins folder and date', () => {
    expect(dailyNotePath(new Date(2026, 3, 21))).toBe('Daily Notes/2026-04-21.md')
  })

  it('uses the expected folder constant', () => {
    expect(DAILY_NOTES_FOLDER).toBe('Daily Notes')
  })
})
