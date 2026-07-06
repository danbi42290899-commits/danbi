import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // Relative asset paths so the production build also works when loaded
  // directly from disk via file:// (Electron's BrowserWindow.loadFile),
  // not just when served from a web server root.
  base: './',
})
