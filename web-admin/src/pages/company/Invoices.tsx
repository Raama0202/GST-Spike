import { useEffect, useState, type KeyboardEvent } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { AlertTriangle, Check, CornerUpLeft, Download, FileSpreadsheet, Receipt, RotateCcw, Search, X } from 'lucide-react'
import { api, apiBlob } from '../../api/client'
import type { EmployeesPage, GstinStatus, Invoice, Page } from '../../api/types'
import { GSTIN_PROBLEMS, GSTIN_STATUS, GstinBadge } from '../../lib/gstin'
import { AsyncPicker } from '../../components/Picker'
import { Badge, Card, Empty, ErrorState, Loading, PageHeader, Pagination, Spinner, useAsync, useDebounced, useToast } from '../../components/ui'
import { date, downloadBlob, money, todayStamp } from '../../lib/format'
import { loadBranches, loadCategories } from '../../lib/lookups'
import {
  DECISION_STATUS, DecisionDialog, InvoiceThumb, PAGE_SIZE, SORTS, STATUSES, invoiceQuery, saveInvoiceNav, vendorOf, type Decision,
} from './InvoiceParts'
const NO_SELECTION = new Set<string>()

function searchEmployees(q: string) {
  return api<EmployeesPage>('/admin/employees', { query: { q: q || undefined, pageSize: 20 } })
    .then((r) => r.items.map((e) => ({ id: e.id, label: e.name, sub: [e.employeeCode, e.branchName].filter(Boolean).join(' · ') })))
}

export default function Invoices() {
  const navigate = useNavigate()
  const toast = useToast()
  const [params, setParams] = useSearchParams()
  const status = params.get('status') ?? 'all'
  const page = Math.max(1, Number(params.get('page') ?? '1') || 1)
  const query = invoiceQuery(params)
  const queryKey = JSON.stringify(query)

  const q = params.get('q') ?? ''
  const [search, setSearch] = useState(q)
  const debouncedSearch = useDebounced(search.trim())
  useEffect(() => {
    if (debouncedSearch !== q) update({ q: debouncedSearch })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debouncedSearch])
  useEffect(() => setSearch((s) => (s.trim() === q ? s : q)), [q])

  const lookups = useAsync(async () => {
    const [branches, categories] = await Promise.all([loadBranches(), loadCategories()])
    return { branches, categories }
  })

  const result = useAsync(
    () => api<Page<Invoice>>('/admin/invoices', { query: { ...query, page, pageSize: PAGE_SIZE } }),
    [queryKey, page],
  )
  const { error, loading, reload } = result
  const items = result.data?.items ?? null

  useEffect(() => {
    if (!result.data) return
    saveInvoiceNav({
      ids: result.data.items.map((x) => x.id),
      query,
      page,
      pageSize: PAGE_SIZE,
      total: result.data.total,
      search: params.toString(),
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [result.data])

  const selectionKey = `${queryKey}|${page}`
  const [selection, setSelection] = useState({ key: selectionKey, ids: NO_SELECTION })
  const selected = selection.key === selectionKey ? selection.ids : NO_SELECTION
  const setSelected = (ids: Set<string>) => setSelection({ key: selectionKey, ids })
  const allOnPage = Boolean(items?.length) && items!.every((x) => selected.has(x.id))

  const [bulk, setBulk] = useState<Decision | null>(null)
  const [exporting, setExporting] = useState<'csv' | 'xlsx' | null>(null)

  function update(patch: Record<string, string>) {
    const next = new URLSearchParams(params)
    for (const [key, value] of Object.entries(patch)) {
      if (value && value !== 'all') next.set(key, value)
      else next.delete(key)
    }
    if (!('page' in patch)) next.delete('page')
    setParams(next)
  }

  function toggle(id: string) {
    const next = new Set(selected)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    setSelected(next)
  }

  function open(id: string) {
    navigate(`/invoices/${id}`)
  }

  function onRowKey(e: KeyboardEvent<HTMLTableRowElement>, id: string) {
    if (e.target !== e.currentTarget) return
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      open(id)
    }
  }

  async function exportAs(format: 'csv' | 'xlsx') {
    setExporting(format)
    try {
      const { blob, filename } = await apiBlob('/admin/invoices/export', { ...query, format }, `invoices-${todayStamp()}.${format}`)
      downloadBlob(filename, blob)
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Export failed', 'error')
    } finally {
      setExporting(null)
    }
  }

  async function runBulk(decision: Decision, remarks: string | null) {
    const res = await api<{ updated: number; skipped: number }>('/admin/invoices/bulk-decision', {
      method: 'POST',
      body: { ids: [...selected], status: DECISION_STATUS[decision], remarks },
    })
    toast(`${res.updated} invoice${res.updated === 1 ? '' : 's'} ${DECISION_STATUS[decision]}${res.skipped ? ` · ${res.skipped} skipped` : ''}`)
    setSelected(new Set())
    await reload()
  }

  const hasFilters = Object.keys(query).some((k) => k !== 'sort') || status !== 'all'
  const employeeLabel = params.get('employeeName') ?? items?.find((x) => x.employeeId === query.employeeId)?.employeeName ?? null
  const categories = lookups.data?.categories ?? []
  const branches = lookups.data?.branches ?? []

  return (
    <>
      <PageHeader
        title="Invoices"
        subtitle="Review, approve, reject or return bills submitted by employees."
        actions={
          <>
            <button className="btn" onClick={() => exportAs('csv')} disabled={exporting !== null}>
              {exporting === 'csv' ? <Spinner small /> : <Download size={16} />} Export CSV
            </button>
            <button className="btn" onClick={() => exportAs('xlsx')} disabled={exporting !== null}>
              {exporting === 'xlsx' ? <Spinner small /> : <FileSpreadsheet size={16} />} Export Excel
            </button>
          </>
        }
      />
      <Card>
        <div className="stack" style={{ gap: 14, marginBottom: 16 }}>
          <div className="row wrap between">
            <div className="segmented" role="group" aria-label="Status">
              {STATUSES.map((s) => (
                <button key={s} className={status === s ? 'on' : ''} aria-pressed={status === s} onClick={() => update({ status: s })}>
                  {s[0].toUpperCase() + s.slice(1)}
                </button>
              ))}
            </div>
            <select className="select" style={{ width: 210 }} value={query.sort ?? 'uploaded_desc'} onChange={(e) => update({ sort: e.target.value === 'uploaded_desc' ? '' : e.target.value })} aria-label="Sort">
              {SORTS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
          </div>
          <div className="filters">
            <div className="input-icon" style={{ width: 250 }}>
              <Search size={16} />
              <input className="input" placeholder="Vendor, GSTIN or invoice no." value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search invoices" />
            </div>
            <AsyncPicker
              value={query.employeeId ?? ''}
              valueLabel={employeeLabel}
              onChange={(id, label) => update({ employeeId: id, employeeName: label })}
              search={searchEmployees}
              allLabel="All employees"
              ariaLabel="Employee"
              placeholder="Search employees…"
            />
            <select className="select" value={query.branchId ?? ''} onChange={(e) => update({ branchId: e.target.value })} aria-label="Branch">
              <option value="">All branches</option>
              {branches.map((b) => <option key={b.id} value={b.id}>{b.name}{b.isActive ? '' : ' (archived)'}</option>)}
            </select>
            <select className="select" value={query.categoryId ?? ''} onChange={(e) => update({ categoryId: e.target.value })} aria-label="Category">
              <option value="">All categories</option>
              {categories.map((c) => <option key={c.id} value={c.id}>{c.name}{c.isActive ? '' : ' (archived)'}</option>)}
            </select>
            <select className="select" value={query.gstinStatus ?? ''} onChange={(e) => update({ gstinStatus: e.target.value })} aria-label="Supplier GSTIN status">
              <option value="">Any GSTIN status</option>
              <option value="problem">GSTIN problems</option>
              {(Object.keys(GSTIN_STATUS) as GstinStatus[]).map((s) => <option key={s} value={s}>{GSTIN_STATUS[s].label}</option>)}
            </select>
            <div className="inline-group" role="group" aria-label="Invoice date range">
              <span>Invoice date</span>
              <input className="input" style={{ width: 155 }} type="date" value={query.dateFrom ?? ''} max={query.dateTo} onChange={(e) => update({ dateFrom: e.target.value })} aria-label="From date" />
              <span>to</span>
              <input className="input" style={{ width: 155 }} type="date" value={query.dateTo ?? ''} min={query.dateFrom} onChange={(e) => update({ dateTo: e.target.value })} aria-label="To date" />
            </div>
            {hasFilters && <button className="btn sm ghost" onClick={() => { setSearch(''); setParams(new URLSearchParams()) }}><RotateCcw size={14} /> Clear filters</button>}
          </div>
        </div>

        {selected.size > 0 && (
          <div className="bulk-bar" role="region" aria-label="Bulk actions">
            <span className="count-label">{selected.size} selected</span>
            <button className="btn sm success" onClick={() => setBulk('approve')}><Check size={14} /> Approve</button>
            <button className="btn sm warn" onClick={() => setBulk('return')}><CornerUpLeft size={14} /> Return</button>
            <button className="btn sm danger" onClick={() => setBulk('reject')}><X size={14} /> Reject</button>
            <button className="btn sm ghost" onClick={() => setSelected(new Set())}>Clear</button>
          </div>
        )}

        {loading && !items ? <Loading /> : error ? <ErrorState message={error} onRetry={reload} /> : !items?.length ? (
          <Empty icon={<Receipt size={24} />} title="No invoices found" message={hasFilters ? 'Try clearing the filters.' : 'Bills scanned in the employee apps will appear here.'} />
        ) : (
          <>
            <div className="table-wrap">
              <table className="table">
                <thead>
                  <tr>
                    <th className="check-cell">
                      <input
                        type="checkbox"
                        className="check"
                        checked={allOnPage}
                        onChange={() => setSelected(allOnPage ? new Set() : new Set(items.map((x) => x.id)))}
                        aria-label="Select all invoices on this page"
                      />
                    </th>
                    <th>Vendor</th><th>Employee</th><th>Category</th><th>Invoice date</th><th>Invoice value</th><th>Status</th><th>Uploaded</th>
                  </tr>
                </thead>
                <tbody>
                  {items.map((inv) => {
                    const vendor = vendorOf(inv)
                    return (
                      <tr key={inv.id} className="clickable" tabIndex={0} onClick={() => open(inv.id)} onKeyDown={(e) => onRowKey(e, inv.id)}>
                        <td className="check-cell" onClick={(e) => e.stopPropagation()}>
                          <input type="checkbox" className="check" checked={selected.has(inv.id)} onChange={() => toggle(inv.id)} aria-label={`Select ${vendor} ${inv.invoiceNumber ?? ''}`} />
                        </td>
                        <td>
                          <div className="row">
                            <InvoiceThumb invoice={inv} />
                            <div style={{ minWidth: 0 }}>
                              <div className="cell-title">{vendor}</div>
                              <div className="cell-sub mono">{inv.invoiceNumber || 'No invoice number'}{inv.gstin ? ` · ${inv.gstin}` : ''}</div>
                              {inv.vendorIsCompany && (
                                <div className="cell-sub" style={{ color: 'var(--warning)' }} title="The scanned vendor matches your own firm's GSTIN or name. Check that the supplier was read correctly.">
                                  <AlertTriangle size={12} style={{ verticalAlign: -1 }} /> Vendor looks like your own firm
                                </div>
                              )}
                              {inv.gstinCheck && GSTIN_PROBLEMS.includes(inv.gstinCheck.status) && (
                                <div className="cell-sub" style={{ marginTop: 4 }} title={inv.gstinCheck.message ?? undefined}>
                                  <GstinBadge status={inv.gstinCheck.status} />
                                </div>
                              )}
                            </div>
                          </div>
                        </td>
                        <td>
                          <div>{inv.employeeName || <span className="faint">—</span>}</div>
                          <div className="cell-sub">{[inv.employeeCode, inv.branchName].filter(Boolean).join(' · ')}</div>
                        </td>
                        <td>{inv.categoryName || String(inv.editedData?.expenseCategoryName ?? '') || <span className="faint">—</span>}</td>
                        <td className="nowrap">{date(inv.invoiceDate)}</td>
                        <td className="nowrap cell-title">{money(inv.netAmount)}</td>
                        <td><Badge status={inv.approvalStatus} /></td>
                        <td className="faint nowrap">{date(inv.uploadedAt, true)}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
            <Pagination page={page} pageSize={PAGE_SIZE} total={result.data?.total ?? 0} onPage={(p) => update({ page: String(p) })} />
          </>
        )}
      </Card>

      {bulk && (
        <DecisionDialog
          decision={bulk}
          count={selected.size}
          onSubmit={(remarks) => runBulk(bulk, remarks)}
          onClose={() => setBulk(null)}
        />
      )}
    </>
  )
}
