import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { createHashRouter, RouterProvider } from 'react-router-dom'
import App from './App'
import { AuthProvider } from './auth/AuthContext'
import { Backdrop, ToastProvider } from './components/ui'
import { initMonitoring } from './lib/monitoring'
import './styles.css'

initMonitoring()

// A data router (rather than <HashRouter>) so pages can use useBlocker for unsaved-changes prompts.
const router = createHashRouter([
  {
    path: '*',
    element: (
      <AuthProvider>
        <ToastProvider>
          <Backdrop />
          <App />
        </ToastProvider>
      </AuthProvider>
    ),
  },
])

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <RouterProvider router={router} />
  </StrictMode>,
)
