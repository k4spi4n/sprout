import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import App from './App.jsx'
import { mockFetch } from './test/fetchMock.js'

const MONTY = { id: 1, name: 'Monty', species: 'Monstera deliciosa', location: 'Living room', water_every_days: 7 }

describe('App', () => {
  it('renders plants returned by the API', async () => {
    mockFetch({ 'GET /api/plants': { body: [MONTY] } })
    render(<App />)

    expect(await screen.findByText('Monty')).toBeTruthy()
    expect(screen.getByText('Monstera deliciosa')).toBeTruthy()
    expect(screen.getByText(/Living room/)).toBeTruthy()
    expect(screen.getByText(/Water weekly/)).toBeTruthy()
  })

  it('shows an empty state when there are no plants', async () => {
    mockFetch({ 'GET /api/plants': { body: [] } })
    render(<App />)

    expect(await screen.findByText(/No plants yet/)).toBeTruthy()
  })

  it('shows an error when the API is down', async () => {
    mockFetch({ 'GET /api/plants': { status: 502, body: null } })
    render(<App />)

    expect(await screen.findByText(/Could not load plants/)).toBeTruthy()
  })

  it('adds a newly created plant to the top of the list', async () => {
    const user = userEvent.setup()
    mockFetch({
      'GET /api/plants': { body: [MONTY] },
      'POST /api/plants': (init) => ({ status: 201, body: { id: 2, ...JSON.parse(init.body) } }),
    })
    render(<App />)
    await screen.findByText('Monty')

    await user.type(screen.getByLabelText('Name'), 'Fern')
    await user.click(screen.getByRole('button', { name: 'Add plant' }))

    const headings = await screen.findAllByRole('heading', { level: 3 })
    expect(headings.map((h) => h.textContent)).toEqual(['Fern', 'Monty'])
  })
})
