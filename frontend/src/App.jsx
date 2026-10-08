import { useEffect, useState } from 'react'
import { api } from './api.js'
import PlantForm from './PlantForm.jsx'
import { describeSchedule } from './schedule.js'

export default function App() {
  const [plants, setPlants] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    api
      .listPlants()
      .then(setPlants)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false))
  }, [])

  async function handleCreate(plant) {
    const created = await api.createPlant(plant)
    setPlants((prev) => [created, ...prev])
  }

  return (
    <main className="container">
      <header className="header">
        <h1>🌱 Sprout</h1>
        <p className="muted">Keep your houseplants alive, one watering at a time.</p>
      </header>

      <PlantForm onSubmit={handleCreate} />

      <section>
        <h2>Your plants</h2>
        {loading && <p className="muted">Loading…</p>}
        {error && <p className="error">Could not load plants: {error}</p>}
        {!loading && !error && plants.length === 0 && (
          <p className="muted">No plants yet. Add your first one above.</p>
        )}
        <ul className="grid">
          {plants.map((p) => (
            <li key={p.id} className="card">
              <h3>{p.name}</h3>
              {p.species && <p className="species">{p.species}</p>}
              <p className="meta">
                {p.location && <span>📍 {p.location}</span>}
                <span>💧 {describeSchedule(p.water_every_days)}</span>
              </p>
              {/* Roadmap: status badge (thirsty / ok), "Water now" button, care history */}
            </li>
          ))}
        </ul>
      </section>
    </main>
  )
}
