import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { CalendarClock, CreditCard, Receipt, ShieldCheck, Users } from 'lucide-react'
import { api } from '../../api/client'
import type { BillingOverview, CheckoutOrder } from '../../api/types'
import { useAuth } from '../../auth/AuthContext'
import { Alert, Badge, Card, Empty, ErrorState, Field, Loading, PageHeader, Spinner, Stat, useAsync, useToast } from '../../components/ui'
import { date, money, toNumber } from '../../lib/format'

const MONTH_OPTIONS = [1, 3, 6, 12]
const CHECKOUT_SRC = 'https://checkout.razorpay.com/v1/checkout.js'

interface RazorpayResponse {
  razorpay_order_id: string
  razorpay_payment_id: string
  razorpay_signature: string
}

interface RazorpayInstance {
  open: () => void
  on: (event: string, cb: (payload: { error?: { description?: string } }) => void) => void
}

declare global {
  interface Window {
    Razorpay?: new (options: Record<string, unknown>) => RazorpayInstance
  }
}

function loadCheckout(): Promise<void> {
  if (window.Razorpay) return Promise.resolve()
  return new Promise((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>(`script[src="${CHECKOUT_SRC}"]`)
    const script = existing ?? document.createElement('script')
    script.src = CHECKOUT_SRC
    script.async = true
    script.onload = () => resolve()
    script.onerror = () => reject(new Error('Could not load Razorpay checkout. Check your connection or ad blocker.'))
    if (!existing) document.body.appendChild(script)
  })
}

export default function Billing() {
  const toast = useToast()
  const navigate = useNavigate()
  const { session, updateSession } = useAuth()
  const { data, error, loading, reload } = useAsync(() => api<BillingOverview>('/admin/billing'))
  const [planCode, setPlanCode] = useState('')
  const [seats, setSeats] = useState('')
  const [months, setMonths] = useState(1)
  const [busy, setBusy] = useState(false)
  const [payError, setPayError] = useState<string | null>(null)

  useEffect(() => {
    if (!data) return
    setPlanCode((p) => p || data.subscription?.planCode || data.plans[0]?.code || '')
    setSeats((s) => s || String(data.subscription?.seats ?? 10))
  }, [data])

  const plan = data?.plans.find((p) => p.code === planCode)
  const seatCount = Number(seats)
  const seatError = !seatCount || seatCount < 1
    ? 'Enter the number of employee seats'
    : plan?.maxEmployees && seatCount > plan.maxEmployees ? `${plan.name} allows up to ${plan.maxEmployees} employees` : null

  const quote = useMemo(() => {
    const price = toNumber(plan?.monthlyPriceInr) ?? 0
    const subtotal = price * months
    const tax = Math.round(subtotal * (data?.taxPercent ?? 0)) / 100
    return { subtotal, tax, total: subtotal + tax }
  }, [plan, months, data?.taxPercent])

  async function pay() {
    if (!data || !plan || seatError) return
    setBusy(true)
    setPayError(null)
    try {
      await loadCheckout()
      const order = await api<CheckoutOrder>('/admin/billing/orders', { method: 'POST', body: { planCode, seats: seatCount, months } })
      const checkout = new window.Razorpay!({
        key: order.keyId,
        order_id: order.orderId,
        amount: order.amountPaise,
        currency: order.currency,
        name: 'GST Expense Scanner',
        description: order.description,
        prefill: { email: order.prefillEmail ?? session?.email ?? '' },
        notes: { company: order.companyName ?? '' },
        theme: { color: '#6d8cff' },
        modal: { ondismiss: () => setBusy(false) },
        handler: async (response: RazorpayResponse) => {
          try {
            await api('/admin/billing/verify', {
              method: 'POST',
              body: {
                razorpayOrderId: response.razorpay_order_id,
                razorpayPaymentId: response.razorpay_payment_id,
                razorpaySignature: response.razorpay_signature,
              },
            })
            toast('Payment received — your subscription is active')
            const wasBlocked = session?.billingRequired
            updateSession({ billingRequired: false })
            await reload()
            if (wasBlocked) navigate('/dashboard', { replace: true })
          } catch (e) {
            setPayError(e instanceof Error ? `${e.message}. If money was debited, it will be applied automatically within a few minutes.` : 'Verification failed')
          } finally {
            setBusy(false)
          }
        },
      })
      checkout.on('payment.failed', (payload) => {
        setPayError(payload.error?.description ?? 'Payment failed. No money was taken; please try again.')
        setBusy(false)
      })
      checkout.open()
    } catch (e) {
      setPayError(e instanceof Error ? e.message : 'Could not start checkout')
      setBusy(false)
    }
  }

  if (loading && !data) return <><PageHeader title="Billing" /><Card><Loading /></Card></>
  if (error || !data) return <><PageHeader title="Billing" /><Card><ErrorState message={error ?? ''} onRetry={reload} /></Card></>

  const sub = data.subscription
  const daysLeft = sub ? Math.ceil((new Date(sub.endsAt).getTime() - Date.now()) / 86400000) : 0

  return (
    <>
      <PageHeader title="Billing" subtitle="Your subscription, renewals and payment history." />
      <div className="stack">
        {session?.billingRequired && (
          <Alert kind="error">Your subscription has expired. Renew below to restore access for your admins and employees on web, Android and iOS.</Alert>
        )}
        <div className="grid cols-3">
          <Stat icon={<ShieldCheck size={20} />} label="Plan" value={data.plans.find((p) => p.code === sub?.planCode)?.name ?? sub?.planCode ?? '—'} tone="#7c9cff" />
          <Stat icon={<Users size={20} />} label="Employee seats" value={sub?.seats ?? '—'} tone="#34d399" />
          <Stat
            icon={<CalendarClock size={20} />}
            label={sub?.isActive ? `Renews / ends ${date(sub.endsAt)}` : 'Expired'}
            value={sub?.isActive ? `${daysLeft} day${daysLeft === 1 ? '' : 's'} left` : sub ? date(sub.endsAt) : '—'}
            tone={sub?.isActive && daysLeft > 7 ? '#34d399' : '#f87171'}
          />
        </div>

        <div className="grid cols-3">
          <Card title="Renew or upgrade" subtitle="Time is added to your current end date." className="span-2">
            {!data.paymentsEnabled ? (
              <Alert kind="info">Online payments are being set up. To renew now, contact your account manager — they can extend your subscription instantly.</Alert>
            ) : (
              <div className="stack">
                {payError && <Alert kind="error">{payError}</Alert>}
                <div className="form-grid">
                  <Field label="Plan">
                    <select className="select" value={planCode} onChange={(e) => setPlanCode(e.target.value)}>
                      {data.plans.map((p) => (
                        <option key={p.code} value={p.code}>{p.name} — {money(p.monthlyPriceInr)}/month{p.maxEmployees ? ` · up to ${p.maxEmployees}` : ' · unlimited'}</option>
                      ))}
                    </select>
                  </Field>
                  <Field label="Employee seats" hint={plan?.maxEmployees ? `max ${plan.maxEmployees}` : undefined}>
                    <input className="input" type="number" min={1} value={seats} onChange={(e) => setSeats(e.target.value)} />
                  </Field>
                </div>
                <div>
                  <div className="faint" style={{ fontSize: 12.5, marginBottom: 8 }}>Billing period</div>
                  <div className="segmented">
                    {MONTH_OPTIONS.map((m) => (
                      <button key={m} className={months === m ? 'on' : ''} onClick={() => setMonths(m)}>{m === 12 ? '1 year' : `${m} month${m > 1 ? 's' : ''}`}</button>
                    ))}
                  </div>
                </div>
                {seatError && seats && <div className="faint" style={{ color: '#fca5a5', fontSize: 12.5 }}>{seatError}</div>}
                <dl className="kv">
                  <dt>Subtotal</dt><dd>{money(quote.subtotal)}</dd>
                  <dt>GST ({data.taxPercent}%)</dt><dd>{money(quote.tax)}</dd>
                  <dt><b>Total</b></dt><dd><b>{money(quote.total)}</b></dd>
                </dl>
                <button className="btn primary" style={{ alignSelf: 'flex-start' }} disabled={busy || !plan || Boolean(seatError)} onClick={pay}>
                  {busy ? <Spinner small /> : <CreditCard size={16} />} Pay {money(quote.total)}
                </button>
                <div className="faint" style={{ fontSize: 12 }}>Secure checkout by Razorpay — UPI, cards, net banking and wallets.</div>
              </div>
            )}
          </Card>
          <Card title="Payment history" subtitle="Most recent first">
            {data.orders.length === 0 ? <Empty icon={<Receipt size={24} />} title="No payments yet" /> : (
              data.orders.map((o) => (
                <div key={o.id} className="list-item">
                  <div className="dot-icon"><Receipt size={16} /></div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div className="row between">
                      <div className="cell-title">{money(o.amount)}</div>
                      <Badge status={o.status === 'paid' ? 'approved' : o.status === 'failed' ? 'failed' : 'pending'} label={o.status} />
                    </div>
                    <div className="cell-sub">{o.planCode} · {o.seats} seats · {o.months} mo · {date(o.paidAt ?? o.createdAt)}</div>
                    {o.failureReason && <div className="faint" style={{ fontSize: 12 }}>{o.failureReason}</div>}
                  </div>
                </div>
              ))
            )}
          </Card>
        </div>
      </div>
    </>
  )
}
