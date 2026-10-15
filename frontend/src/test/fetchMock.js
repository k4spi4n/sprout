import { vi } from 'vitest'

// Minimal fetch stub. routes: { 'GET /api/plants': { status, body } | (init) => ({ status, body }) }
export function mockFetch(routes) {
  const fn = vi.fn(async (url, init = {}) => {
    const key = `${init.method || 'GET'} ${url}`
    const route = routes[key]
    if (!route) throw new Error(`Unexpected request: ${key}`)
    const { status = 200, body = null } = typeof route === 'function' ? route(init) : route
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    }
  })
  vi.stubGlobal('fetch', fn)
  return fn
}
