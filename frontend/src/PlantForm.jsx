import { useState } from 'react'

const EMPTY = { name: '', species: '', location: '', water_every_days: 7 }

export default function PlantForm({ onSubmit }) {
  const [form, setForm] = useState(EMPTY)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)

  const update = (field) => (e) => setForm({ ...form, [field]: e.target.value })

  async function handleSubmit(e) {
    e.preventDefault()
    setSaving(true)
    setError(null)
    try {
      await onSubmit({
        name: form.name.trim(),
        species: form.species.trim() || null,
        location: form.location.trim() || null,
        water_every_days: Number(form.water_every_days),
      })
      setForm(EMPTY)
    } catch (err) {
      setError(err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <form className="card form" onSubmit={handleSubmit}>
      <h2>Add a plant</h2>
      <div className="fields">
        <label>
          Name
          <input required maxLength={80} value={form.name} onChange={update('name')} placeholder="Monty" />
        </label>
        <label>
          Species
          <input maxLength={120} value={form.species} onChange={update('species')} placeholder="Monstera deliciosa" />
        </label>
        <label>
          Location
          <input maxLength={80} value={form.location} onChange={update('location')} placeholder="Living room" />
        </label>
        <label>
          Water every (days)
          <input type="number" min={1} max={60} required value={form.water_every_days} onChange={update('water_every_days')} />
        </label>
      </div>
      {error && <p className="error">{error}</p>}
      <button type="submit" disabled={saving}>{saving ? 'Saving…' : 'Add plant'}</button>
    </form>
  )
}
