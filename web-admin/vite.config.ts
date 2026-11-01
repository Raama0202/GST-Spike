import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Port 8080 is on the backend's CORS allow-list.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
  server: { port: 8080, strictPort: true, host: '127.0.0.1' },
  preview: { port: 8080, strictPort: true, host: '127.0.0.1' },
})
