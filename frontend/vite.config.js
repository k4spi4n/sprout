import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// In dev, /api is proxied to a local FastAPI (uvicorn on :8000).
// In production, nginx (see nginx.conf) does the same proxying inside Docker.
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: { '/api': 'http://localhost:8000' },
  },
})
