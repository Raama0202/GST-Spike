import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Port 8080 is on the backend's CORS allow-list.
// On Render (RENDER=true) the static site publishes `apps/web/dist` from the
// repo root, so the build is written there instead of `web-admin/dist`.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: process.env.RENDER ? '../apps/web/dist' : 'dist',
    emptyOutDir: true,
  },
  server: { port: 8080, strictPort: true, host: '127.0.0.1' },
  preview: { port: 8080, strictPort: true, host: '127.0.0.1' },
})
