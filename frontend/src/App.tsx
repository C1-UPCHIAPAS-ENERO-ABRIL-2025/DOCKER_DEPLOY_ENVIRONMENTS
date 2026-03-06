import { useState, useEffect } from 'react'
import './App.css'

interface Item {
  id: number
  name: string
  quantity: number
}

function App() {
  const [items, setItems] = useState<Item[]>([])
  const [health, setHealth] = useState<string>('checking...')

  useEffect(() => {
    fetch('/api/health')
      .then(r => r.json())
      .then(d => setHealth(d.status))
      .catch(() => setHealth('unreachable'))

    fetch('/api/items')
      .then(r => r.json())
      .then(d => setItems(d))
      .catch(() => setItems([]))
  }, [])

  return (
    <div className="app">
      <header className="header">
        <div className="header-inner">
          <h1 className="logo">Modest<span>Inventary</span></h1>
          <span className={`badge ${health === 'ok' ? 'badge--ok' : 'badge--err'}`}>
            API: {health}
          </span>
        </div>
      </header>

      <main className="main">
        <section className="hero">
          <h2>Inventory Dashboard</h2>
          <p>Certified evidence-grade deployment, running in a hermetic Docker ecosystem.</p>
        </section>

        <section className="grid">
          {items.length === 0 ? (
            <div className="empty">No items found or API not reachable.</div>
          ) : (
            items.map(item => (
              <div className="card" key={item.id}>
                <div className="card-id">#{item.id}</div>
                <h3 className="card-name">{item.name}</h3>
                <div className="card-qty">
                  <span>Qty</span>
                  <strong>{item.quantity}</strong>
                </div>
              </div>
            ))
          )}
        </section>
      </main>
    </div>
  )
}

export default App
