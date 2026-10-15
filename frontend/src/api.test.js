import { describe, expect, it } from 'vitest'
import { api } from './api.js'
import { mockFetch } from './test/fetchMock.js'

describe('api', () => {
  it('lists plants from /api/plants', async () => {
    mockFetch({ 'GET /api/plants': { body: [{ id: 1, name: 'Monty' }] } })
    await expect(api.listPlants()).resolves.toEqual([{ id: 1, name: 'Monty' }])
  })

  it('POSTs a JSON body when creating a plant', async () => {
    const fetch = mockFetch({
      'POST /api/plants': (init) => ({ status: 201, body: { id: 2, ...JSON.parse(init.body) } }),
    })
    const created = await api.createPlant({ name: 'Fern', water_every_days: 3 })

    expect(created).toEqual({ id: 2, name: 'Fern', water_every_days: 3 })
    expect(fetch.mock.calls[0][1].headers['Content-Type']).toBe('application/json')
  })

  it('surfaces the API error message', async () => {
    mockFetch({ 'GET /api/health': { status: 503, body: { detail: 'Database unavailable' } } })
    await expect(api.health()).rejects.toThrow('Database unavailable')
  })

  it('falls back to the status code when there is no message', async () => {
    mockFetch({ 'POST /api/plants': { status: 422, body: { detail: [{ msg: 'invalid' }] } } })
    await expect(api.createPlant({})).rejects.toThrow('Request failed (422)')
  })
})
