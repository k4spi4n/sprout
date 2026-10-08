export function describeSchedule(days) {
  if (days === 1) return 'Water daily'
  if (days === 7) return 'Water weekly'
  if (days % 7 === 0) return `Water every ${days / 7} weeks`
  return `Water every ${days} days`
}
