import { useEffect, useId, useRef, useState, type KeyboardEvent } from 'react'
import { useDebounced } from './ui'

export interface PickerOption {
  id: string
  label: string
  sub?: string | null
}

/**
 * Searchable single-select that queries the API as you type, so large lists
 * (employees, companies) are never loaded up front.
 */
export function AsyncPicker({ value, valueLabel, onChange, search, allLabel, placeholder = 'Type to search…', ariaLabel, width = 220 }: {
  value: string
  valueLabel?: string | null
  onChange: (id: string, label: string) => void
  search: (query: string) => Promise<PickerOption[]>
  allLabel: string
  placeholder?: string
  ariaLabel: string
  width?: number
}) {
  const listId = useId()
  const [open, setOpen] = useState(false)
  const [text, setText] = useState('')
  const [options, setOptions] = useState<PickerOption[] | null>(null)
  const [loading, setLoading] = useState(false)
  const [active, setActive] = useState(0)
  const query = useDebounced(text.trim(), 250)
  const searchRef = useRef(search)
  searchRef.current = search

  useEffect(() => {
    if (!open) return
    let cancelled = false
    setLoading(true)
    searchRef.current(query)
      .then((found) => { if (!cancelled) setOptions(found) })
      .catch(() => { if (!cancelled) setOptions([]) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [open, query])

  const items: PickerOption[] = [{ id: '', label: allLabel }, ...(options ?? [])]

  function choose(option: PickerOption) {
    onChange(option.id, option.id ? option.label : '')
    setOpen(false)
    setText('')
  }

  function onKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (!open && (e.key === 'ArrowDown' || e.key === 'Enter')) {
      setOpen(true)
      return
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActive((i) => Math.min(items.length - 1, i + 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActive((i) => Math.max(0, i - 1))
    } else if (e.key === 'Enter' && open) {
      e.preventDefault()
      const option = items[active]
      if (option) choose(option)
    } else if (e.key === 'Escape' && open) {
      e.preventDefault()
      e.stopPropagation()
      setOpen(false)
      setText('')
    }
  }

  return (
    <div className="picker" style={{ width }}>
      <input
        className="input"
        role="combobox"
        aria-label={ariaLabel}
        aria-expanded={open}
        aria-controls={listId}
        aria-autocomplete="list"
        aria-activedescendant={open ? `${listId}-${active}` : undefined}
        value={open ? text : value ? valueLabel || 'Selected' : ''}
        placeholder={open ? placeholder : allLabel}
        onFocus={() => { setOpen(true); setText(''); setActive(0) }}
        onBlur={() => { setOpen(false); setText('') }}
        onChange={(e) => { setText(e.target.value); setActive(0); setOpen(true) }}
        onKeyDown={onKeyDown}
      />
      {open && (
        <ul id={listId} role="listbox" className="picker-list" aria-label={ariaLabel}>
          {items.map((option, i) => (
            <li
              key={option.id || 'all'}
              id={`${listId}-${i}`}
              role="option"
              aria-selected={i === active}
              onMouseDown={(e) => { e.preventDefault(); choose(option) }}
              onMouseEnter={() => setActive(i)}
            >
              <div>{option.label}</div>
              {option.sub && <div className="cell-sub">{option.sub}</div>}
            </li>
          ))}
          {loading && <li className="muted-item" role="presentation">Searching…</li>}
          {!loading && options?.length === 0 && <li className="muted-item" role="presentation">No matches</li>}
        </ul>
      )}
    </div>
  )
}
