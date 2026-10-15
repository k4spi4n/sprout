import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// In dev, /api is proxied to a local FastAPI (uvicorn on :8000).
// In production, nginx (see nginx.conf) does the same proxying inside Docker.
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: { '/api': 'http://localhost:8000' },
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.js'],
    coverage: {
      provider: 'v8',
      include: ['src/**/*.{js,jsx}'],
      exclude: ['src/main.jsx', 'src/test/**', 'src/**/*.test.{js,jsx}'],
      // lcov is read by SonarQube; text is printed in the Jenkins log
      reporter: ['text', 'lcov'],
      reportsDirectory: 'reports/coverage',
      thresholds: { statements: 80, branches: 80, functions: 80, lines: 80 },
    },
  },
})
