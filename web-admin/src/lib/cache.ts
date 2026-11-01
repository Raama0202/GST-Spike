/** Short-lived promise cache for small lookup lists (branches, categories) shared across pages. */
const store = new Map<string, { at: number; promise: Promise<unknown> }>()

export function cached<T>(key: string, loader: () => Promise<T>, ttlMs = 60_000): Promise<T> {
  const hit = store.get(key)
  if (hit && Date.now() - hit.at < ttlMs) return hit.promise as Promise<T>
  const promise = loader()
  store.set(key, { at: Date.now(), promise })
  promise.catch(() => {
    if (store.get(key)?.promise === promise) store.delete(key)
  })
  return promise
}

export function invalidate(prefix = '') {
  for (const key of [...store.keys()]) if (key.startsWith(prefix)) store.delete(key)
}
