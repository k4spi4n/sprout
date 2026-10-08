async function request(path, options = {}) {
  const res = await fetch(`/api${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    throw new Error(typeof body.detail === 'string' ? body.detail : `Request failed (${res.status})`)
  }
  return res.status === 204 ? null : res.json()
}

export const api = {
  health: () => request('/health'),
  listPlants: () => request('/plants'),
  createPlant: (plant) => request('/plants', { method: 'POST', body: JSON.stringify(plant) }),
}
