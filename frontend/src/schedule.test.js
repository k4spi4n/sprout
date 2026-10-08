import { describe, expect, it } from 'vitest'
import { describeSchedule } from './schedule.js'

describe('describeSchedule', () => {
  it('handles daily and weekly', () => {
    expect(describeSchedule(1)).toBe('Water daily')
    expect(describeSchedule(7)).toBe('Water weekly')
  })

  it('uses weeks for multiples of 7', () => {
    expect(describeSchedule(14)).toBe('Water every 2 weeks')
  })

  it('falls back to days', () => {
    expect(describeSchedule(3)).toBe('Water every 3 days')
  })
})
