import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, Printer } from 'lucide-react'
import { api } from '../api/client'
import type { BillingInvoice } from '../api/types'
import { Card, ErrorState, Loading, PageHeader, useAsync, useDocumentTitle } from '../components/ui'
import { date, money, toNumber } from '../lib/format'

function Party({ label, party }: { label: string; party: BillingInvoice['seller'] }) {
  return (
    <div>
      <div className="inv-label">{label}</div>
      <div className="inv-strong">{party.legalName || party.name}</div>
      {party.legalName && party.name && party.legalName !== party.name && <div>{party.name}</div>}
      {party.address && <div style={{ whiteSpace: 'pre-line' }}>{party.address}</div>}
      {party.state && <div>State: {party.state.name} ({party.state.code})</div>}
      <div>GSTIN: {party.gstin ?? (label === 'Billed to' ? 'Unregistered' : 'Not registered')}</div>
      {party.email && <div>{party.email}</div>}
      {party.phone && <div>{party.phone}</div>}
    </div>
  )
}

export default function BillingInvoicePage({ scope }: { scope: 'company' | 'super' }) {
  const { id = '' } = useParams()
  const path = scope === 'super' ? `/super/payments/${id}/invoice` : `/admin/billing/orders/${id}/invoice`
  const back = scope === 'super' ? '/super/payments' : '/billing'
  const { data: inv, error, loading, reload } = useAsync(() => api<BillingInvoice>(path), [path])
  useDocumentTitle(inv ? `${inv.title} ${inv.number}` : 'Invoice')

  const header = (
    <PageHeader
      title={inv ? `${inv.title} ${inv.number}` : 'Invoice'}
      subtitle="Print or save as PDF for your accounts."
      actions={
        <>
          <Link className="btn" to={back}><ArrowLeft size={16} /> Back</Link>
          <button className="btn primary" disabled={!inv} onClick={() => window.print()}><Printer size={16} /> Print / Save PDF</button>
        </>
      }
    />
  )
  if (loading && !inv) return <>{header}<Card><Loading /></Card></>
  if (error || !inv) return <>{header}<Card><ErrorState message={error ?? 'Invoice not found'} onRetry={reload} /></Card></>

  const intra = (toNumber(inv.cgst) ?? 0) > 0
  const half = (toNumber(inv.taxPercent) ?? 0) / 2
  const refunded = toNumber(inv.refundedAmount) ?? 0
  return (
    <>
      <div className="no-print">{header}</div>
      <article className="invoice-sheet" aria-label={`${inv.title} ${inv.number}`}>
        <header className="inv-top">
          <div>
            <div className="inv-title">{inv.title.toUpperCase()}</div>
            <div className="inv-muted">Original for recipient</div>
          </div>
          <dl className="inv-meta">
            <dt>Invoice no.</dt><dd>{inv.number}</dd>
            <dt>Date</dt><dd>{date(inv.issuedAt)}</dd>
            <dt>Place of supply</dt><dd>{inv.placeOfSupply ? `${inv.placeOfSupply.name} (${inv.placeOfSupply.code})` : '—'}</dd>
            <dt>Reverse charge</dt><dd>{inv.reverseCharge ? 'Yes' : 'No'}</dd>
          </dl>
        </header>
        <section className="inv-parties">
          <Party label="Supplier" party={inv.seller} />
          <Party label="Billed to" party={inv.buyer} />
        </section>
        <table className="inv-table">
          <thead>
            <tr><th>#</th><th>Description</th><th>SAC</th><th className="right">Qty</th><th className="right">Rate</th><th className="right">Taxable value</th></tr>
          </thead>
          <tbody>
            {inv.lines.map((l, i) => (
              <tr key={i}>
                <td>{i + 1}</td><td>{l.description}</td><td>{l.sac}</td>
                <td className="right">{l.quantity} {l.unit}{l.quantity > 1 ? 's' : ''}</td>
                <td className="right">{money(l.rate)}</td><td className="right">{money(l.amount)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <section className="inv-totals">
          <div className="inv-words"><div className="inv-label">Amount in words</div>{inv.amountInWords}</div>
          <dl>
            <dt>Taxable value</dt><dd>{money(inv.subtotal)}</dd>
            {intra ? (
              <>
                <dt>CGST @ {half}%</dt><dd>{money(inv.cgst)}</dd>
                <dt>SGST @ {half}%</dt><dd>{money(inv.sgst)}</dd>
              </>
            ) : (toNumber(inv.igst) ?? 0) > 0 ? (
              <><dt>IGST @ {toNumber(inv.taxPercent)}%</dt><dd>{money(inv.igst)}</dd></>
            ) : null}
            <dt className="inv-strong">Invoice value</dt><dd className="inv-strong">{money(inv.total)}</dd>
            {refunded > 0 && <><dt>Refunded</dt><dd>− {money(refunded)}</dd></>}
          </dl>
        </section>
        <section className="inv-foot">
          <div>
            <div className="inv-label">Payment</div>
            Paid online via {inv.payment.method ?? 'Razorpay'}{inv.payment.paidAt ? ` on ${date(inv.payment.paidAt, true)}` : ''}
            {inv.payment.paymentId && <div className="mono">Payment ID {inv.payment.paymentId}</div>}
            {inv.payment.orderId && <div className="mono">Order ID {inv.payment.orderId}</div>}
          </div>
          <div className="inv-muted" style={{ textAlign: 'right' }}>
            For {inv.seller.legalName || inv.seller.name}
            <div style={{ marginTop: 6 }}>This is a computer-generated invoice and needs no signature.</div>
          </div>
        </section>
      </article>
    </>
  )
}
