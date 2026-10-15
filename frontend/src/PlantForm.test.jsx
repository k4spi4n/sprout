import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import PlantForm from './PlantForm.jsx'

async function fillAndSubmit(user, { name, species, location, days }) {
  await user.type(screen.getByLabelText('Name'), name)
  if (species) await user.type(screen.getByLabelText('Species'), species)
  if (location) await user.type(screen.getByLabelText('Location'), location)
  if (days) {
    await user.clear(screen.getByLabelText('Water every (days)'))
    await user.type(screen.getByLabelText('Water every (days)'), days)
  }
  await user.click(screen.getByRole('button', { name: 'Add plant' }))
}

describe('PlantForm', () => {
  it('submits trimmed values and a numeric interval, then resets', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn().mockResolvedValue(undefined)
    render(<PlantForm onSubmit={onSubmit} />)

    await fillAndSubmit(user, { name: '  Monty ', species: 'Monstera', location: 'Office', days: '10' })

    expect(onSubmit).toHaveBeenCalledWith({
      name: 'Monty',
      species: 'Monstera',
      location: 'Office',
      water_every_days: 10,
    })
    expect(screen.getByLabelText('Name')).toHaveProperty('value', '')
  })

  it('sends null for empty optional fields', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn().mockResolvedValue(undefined)
    render(<PlantForm onSubmit={onSubmit} />)

    await fillAndSubmit(user, { name: 'Fern' })

    expect(onSubmit).toHaveBeenCalledWith({ name: 'Fern', species: null, location: null, water_every_days: 7 })
  })

  it('shows the error and keeps the input when saving fails', async () => {
    const user = userEvent.setup()
    const onSubmit = vi.fn().mockRejectedValue(new Error('Server exploded'))
    render(<PlantForm onSubmit={onSubmit} />)

    await fillAndSubmit(user, { name: 'Cactus' })

    expect(await screen.findByText('Server exploded')).toBeTruthy()
    expect(screen.getByLabelText('Name')).toHaveProperty('value', 'Cactus')
    expect(screen.getByRole('button', { name: 'Add plant' })).toHaveProperty('disabled', false)
  })
})
