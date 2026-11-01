import { useEffect } from 'react'
import { useBlocker } from 'react-router-dom'
import { Confirm } from './ui'

/** Asks before leaving the page (in-app navigation or tab close) while `when` is true. */
export function UnsavedChangesPrompt({ when }: { when: boolean }) {
  const blocker = useBlocker(({ currentLocation, nextLocation }) => when && currentLocation.pathname !== nextLocation.pathname)

  useEffect(() => {
    if (!when) return
    const onBeforeUnload = (e: BeforeUnloadEvent) => {
      e.preventDefault()
      e.returnValue = ''
    }
    window.addEventListener('beforeunload', onBeforeUnload)
    return () => window.removeEventListener('beforeunload', onBeforeUnload)
  }, [when])

  if (blocker.state !== 'blocked') return null
  return (
    <Confirm
      title="Leave without saving?"
      message="You have unsaved changes on this page. They will be lost if you leave."
      confirmLabel="Leave page"
      danger
      onConfirm={() => blocker.proceed()}
      onClose={() => blocker.reset()}
    />
  )
}
