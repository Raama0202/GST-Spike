import { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { FileImage, Receipt, RotateCcw, Search } from 'lucide-react'
import { api, mediaUrl } from '../../api/client'
import type { Employee, Invoice, Items, NamedResource, Page } from '../../api/types'
import { Badge, Card, Empty, ErrorState, Loading, PageHeader, Pagination, useAsync, useDebounced } from '../../components/ui'
import { date, money } from '../../lib/format'

const STATUSES = ['all', 'pending', 'approved', 'returned', 'rejected'] as const
const PAGE_SIZE = 25

export function InvoiceThumb({ invoice }: { invoice: Invoice }) {
  const [failed, setFailed] = useState(false)
  const src = mediaUrl(invoice.thumbnailUrl ?? invoice.imageUrl)
  return (
    <div className="thumb">
      {src && !failed ? <img src={src} alt="" loading="lazy" onError={() => setFailed(true)} /> : <FileImage size={18} />}
    </div>
  )
}

export default function Invoices() {
  const navigate = useNavigate()
  const [params, setParams] = useSearchParams()
  const status = params.get('status') ?? 'all'
  const employeeId = params.get('employeeId') ?? ''
  const branchId = params.get('branchId') ?? ''
  const dateFrom = params.get('dateFrom') ?? ''
  const dateTo = params.get('dateTo') ?? ''
  const page = Number(params.get('page') ?? '1')

  const q = params.get('q') ?? ''
  const [search, setSearch] = useState(q)
  const debouncedSearch = useDebounced(search.trim())

  useEffect(() => {
    if (debouncedSearch !== q) update('q', debouncedSearch)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debouncedSearch])

  const filters = useAsync(async () => {
    const [employees, branches] = await Promise.all([
      api<Items<Employee>>('/admin/employees', { query: { pageSize: 1000 } }),
      api<Items<NamedResource>>('/admin/company/branches'),
    ])
    return { employees: employees.items, branches: branches.items }
  })

  const result = useAsync(
    () => api<Page<Invoice>>('/admin/invoices', {
      query: {
        status: status === 'all' ? undefined : status,
        employeeId, branchId, dateFrom, dateTo, q: q || undefined, page, pageSize: PAGE_SIZE,
      },
    }),
    [status, employeeId, branchId, dateFrom, dateTo, q, page],
  )
  const { error, loading, reload } = result
  const data = result.data?.items ?? null

  function update(key: string, value: string) {
    const next = new URLSearchParams(params)
    if (value && value !== 'all') next.set(key, value)
    else next.delete(key)
    if (key !== 'page') next.delete('page')
    setParams(next)
  }

  const hasFilters = employeeId || branchId || dateFrom || dateTo || q || status !== 'all'

  return (
    <>
      <PageHeader title="Invoices" subtitle="Review, approve, reject or return bills submitted by employees." />
      <Card>
        <div className="stack" style={{ gap: 14, marginBottom: 16 }}>
          <div className="segmented" style={{ alignSelf: 'flex-start' }}>
            {STATUSES.map((s) => (
              <button key={s} className={status === s ? 'on' : ''} onClick={() => update('status', s)}>
                {s[0].toUpperCase() + s.slice(1)}
              </button>
            ))}
          </div>
          <div className="row wrap">
            <div className="input-icon" style={{ width: 260 }}>
              <Search size={16} />
              <input className="input" placeholder="Vendor, GSTIN or invoice no." value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search invoices" />
            </div>
            <select className="select" style={{ width: 210 }} value={employeeId} onChange={(e) => update('employeeId', e.target.value)} aria-label="Employee">
              <option value="">All employees</option>
              {filters.data?.employees.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}
            </select>
            <select className="select" style={{ width: 180 }} value={branchId} onChange={(e) => update('branchId', e.target.value)} aria-label="Branch">
              <option value="">All branches</option>
              {filters.data?.branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
            <label className="row faint" style={{ gap: 8 }}>
              Invoice date
              <input className="input" style={{ width: 160 }} type="date" value={dateFrom} onChange={(e) => update('dateFrom', e.target.value)} aria-label="From date" />
              <span>to</span>
              <input className="input" style={{ width: 160 }} type="date" value={dateTo} onChange={(e) => update('dateTo', e.target.value)} aria-label="To date" />
            </label>
            {hasFilters && <button className="btn sm ghost" onClick={() => { setSearch(''); setParams(new URLSearchParams()) }}><RotateCcw size={14} /> Clear filters</button>}
          </div>
        </div>

        {loading && !data ? <Loading /> : error ? <ErrorState message={error} onRetry={reload} /> : !data?.length ? (
          <Empty icon={<Receipt size={24} />} title="No invoices found" message={hasFilters ? 'Try clearing the filters.' : 'Bills scanned in the employee apps will appear here.'} />
        ) : (
          <>
            <div className="table-wrap">
              <table className="table">
                <thead>
                  <tr><th>Vendor</th><th>GSTIN</th><th>Invoice date</th><th>Net amount</th><th>Status</th><th>Uploaded</th></tr>
                </thead>
                <tbody>
                  {data.map((inv) => (
                    <tr key={inv.id} className="clickable" onClick={() => navigate(`/invoices/${inv.id}`)}>
                      <td>
                        <div className="row">
                          <InvoiceThumb invoice={inv} />
                          <div>
                            <div className="cell-title">{inv.vendorName || inv.editedData?.vendorName || 'Unknown vendor'}</div>
                            <div className="cell-sub mono">{inv.invoiceNumber || 'No invoice number'}</div>
                          </div>
                        </div>
                      </td>
                      <td className="mono">{inv.gstin || '—'}</td>
                      <td className="nowrap">{date(inv.editedData?.invoiceDate as string | undefined)}</td>
                      <td className="nowrap cell-title">{money(inv.netAmount)}</td>
                      <td><Badge status={inv.approvalStatus} /></td>
                      <td className="faint nowrap">{date(inv.uploadedAt, true)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pagination page={page} pageSize={PAGE_SIZE} total={result.data?.total ?? 0} onPage={(p) => update('page', String(p))} />
          </>
        )}
      </Card>
    </>
  )
}
