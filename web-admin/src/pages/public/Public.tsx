import { useEffect, useState, type ReactNode } from 'react'
import { Link, NavLink } from 'react-router-dom'
import { Check, FileText, Mail, MapPin, Phone, Receipt } from 'lucide-react'
import { api } from '../../api/client'
import type { BusinessInfo, PublicPlans } from '../../api/types'
import { useAuth } from '../../auth/AuthContext'
import { Card, ErrorState, Loading, useAsync, useDocumentTitle } from '../../components/ui'
import { money, toNumber } from '../../lib/format'
import { PUBLIC_LINKS, PublicFooterLinks } from './links'

const FALLBACK: BusinessInfo = {
  name: 'GST Expense', legalName: 'GST Expense', gstin: null, address: null, email: null, phone: null,
  taxPercent: 0, paymentsEnabled: false, trialDays: 14,
}

let businessRequest: Promise<BusinessInfo> | null = null

function loadBusiness(): Promise<BusinessInfo> {
  businessRequest ??= api<BusinessInfo>('/public/business', { auth: false }).catch((e) => {
    businessRequest = null
    throw e
  })
  return businessRequest
}

function useBusiness(): BusinessInfo {
  const [business, setBusiness] = useState<BusinessInfo>(FALLBACK)
  useEffect(() => {
    let live = true
    loadBusiness().then((b) => live && setBusiness(b)).catch(() => {})
    return () => { live = false }
  }, [])
  return business
}

function Shell({ title, updated, children }: { title: string; updated?: boolean; children: (b: BusinessInfo) => ReactNode }) {
  useDocumentTitle(title)
  const { session } = useAuth()
  const business = useBusiness()
  return (
    <div className="public-page">
      <header className="public-head">
        <Link to="/login" className="brand" style={{ padding: 0 }}>
          <div className="brand-mark"><FileText size={20} strokeWidth={2.4} /></div>
          <div>
            <div className="brand-name">{business.name}</div>
            <div className="brand-sub">GST bill capture & ITC for Indian businesses</div>
          </div>
        </Link>
        <Link className="btn primary" to={session ? '/' : '/login'}>{session ? 'Open console' : 'Sign in'}</Link>
      </header>
      <nav className="public-tabs" aria-label="Site">
        {PUBLIC_LINKS.map(([to, label]) => <NavLink key={to} to={to} className={({ isActive }) => (isActive ? 'on' : '')}>{label}</NavLink>)}
      </nav>
      <main className="public-body">
        <h1>{title}</h1>
        {updated && <div className="faint" style={{ marginBottom: 18 }}>Applies to {business.legalName} ("we", "us") and the {business.name} web console, Android and iOS apps.</div>}
        {children(business)}
      </main>
      <footer className="public-foot">
        <PublicFooterLinks />
        <div className="faint">© {new Date().getFullYear()} {business.legalName}{business.gstin ? ` · GSTIN ${business.gstin}` : ''}</div>
      </footer>
    </div>
  )
}

function contactLine(b: BusinessInfo) {
  return b.email ? <a href={`mailto:${b.email}`}>{b.email}</a> : 'the contact details on our Contact us page'
}

export function Pricing() {
  const { data, error, loading, reload } = useAsync(() => api<PublicPlans>('/public/plans', { auth: false }))
  return (
    <Shell title="Pricing">
      {(b) => (
        <>
          <p className="lead">
            Start with a {b.trialDays}-day free trial — no card needed. When it ends, pick a plan from the Billing page of your
            console and pay securely with UPI, cards, net banking or wallets through Razorpay.
          </p>
          {loading && !data ? <Card><Loading /></Card> : error || !data ? <Card><ErrorState message={error ?? ''} onRetry={reload} /></Card> : (
            <div className="price-grid">
              {data.items.map((p) => (
                <div key={p.code} className="glass price-card">
                  <div className="price-name">{p.name}</div>
                  <div className="price-amount">{money(p.monthlyPriceInr)}<span>/month</span></div>
                  <div className="faint">{data.taxPercent ? `+ ${data.taxPercent}% GST` : 'No GST charged'} · billed for 1, 3, 6 or 12 months</div>
                  <ul>
                    <li><Check size={15} /> {p.maxEmployees ? `Up to ${p.maxEmployees} employees` : 'Unlimited employees'}</li>
                    <li><Check size={15} /> Android & iOS bill scanner with AI reading</li>
                    <li><Check size={15} /> Approval workflow and Excel / CSV export</li>
                    <li><Check size={15} /> GSTR-2A/2B ITC matching</li>
                    {(toNumber(p.monthlyPriceInr) ?? 0) > 0 && <li><Check size={15} /> GST tax invoice for every payment</li>}
                  </ul>
                </div>
              ))}
            </div>
          )}
          <p className="faint" style={{ marginTop: 18 }}>Prices are in Indian Rupees. Questions about a plan? Write to {contactLine(b)}.</p>
        </>
      )}
    </Shell>
  )
}

export function Contact() {
  return (
    <Shell title="Contact us">
      {(b) => (
        <div className="grid cols-2">
          <Card title={b.legalName} subtitle={b.gstin ? `GSTIN ${b.gstin}` : undefined}>
            <div className="stack" style={{ gap: 14 }}>
              {b.address && <div className="row" style={{ alignItems: 'flex-start', gap: 10 }}><MapPin size={18} /> <span style={{ whiteSpace: 'pre-line' }}>{b.address}</span></div>}
              {b.email && <div className="row" style={{ gap: 10 }}><Mail size={18} /> <a href={`mailto:${b.email}`}>{b.email}</a></div>}
              {b.phone && <div className="row" style={{ gap: 10 }}><Phone size={18} /> <a href={`tel:${b.phone.replace(/\s/g, '')}`}>{b.phone}</a></div>}
              {!b.address && !b.email && !b.phone && <div className="faint">Contact details are being updated.</div>}
            </div>
          </Card>
          <Card title="Support hours" subtitle="Monday to Saturday, 10:00 – 18:00 IST">
            <div className="stack" style={{ gap: 10 }}>
              <p>We reply to every email within one business day. For billing questions include your company name and the Razorpay payment ID from your receipt.</p>
              <p className="faint"><Receipt size={14} style={{ verticalAlign: -2 }} /> Payment issues are usually resolved the same day.</p>
            </div>
          </Card>
        </div>
      )}
    </Shell>
  )
}

export function Terms() {
  return (
    <Shell title="Terms & conditions" updated>
      {(b) => (
        <div className="prose">
          <h2>1. The service</h2>
          <p>{b.name} lets businesses capture GST bills with a mobile app, review and approve them in a web console, export expense data and match input tax credit against GSTR-2A/2B. The service is provided on a subscription basis to registered businesses.</p>
          <h2>2. Accounts</h2>
          <p>The person registering a company confirms they are authorised to act for it. Company admins are responsible for the employees they invite, for keeping passwords and one-time codes private, and for the accuracy of the data they upload.</p>
          <h2>3. Subscriptions and payment</h2>
          <p>New companies receive a free trial of {b.trialDays} days. After that, access requires an active paid plan. Plans are prepaid for the period chosen at checkout (1, 3, 6 or 12 months) and the time is added to the current end date. Prices are shown in Indian Rupees{b.taxPercent ? ` and GST at ${b.taxPercent}% is added` : ''}. Payments are processed by Razorpay; we never see or store your card or bank details. A tax invoice is issued for every successful payment.</p>
          <h2>4. Expiry</h2>
          <p>We email reminders before a subscription ends. When it ends, admins and employees can sign in only to renew. Your data is retained and becomes available again as soon as you renew.</p>
          <h2>5. Acceptable use</h2>
          <p>Do not upload unlawful content, attempt to access another company's data, overload or reverse-engineer the service, or use it to create false invoices or claim credit you are not entitled to.</p>
          <h2>6. Your data</h2>
          <p>You own the bills and data you upload. We process it only to provide the service, as described in our <Link to="/privacy">Privacy policy</Link>. Bill reading uses automated (AI) extraction; always review amounts and GSTINs before relying on them for tax filings.</p>
          <h2>7. Availability and liability</h2>
          <p>We work to keep the service available and your data backed up, but the service is provided "as is". To the extent permitted by law, our total liability for any claim is limited to the fees you paid in the three months before the claim. We are not liable for tax positions taken on the basis of extracted data.</p>
          <h2>8. Termination</h2>
          <p>You may stop using the service at any time; see our <Link to="/refund-policy">Refund & cancellation policy</Link>. We may suspend accounts that breach these terms or remain unpaid.</p>
          <h2>9. Governing law</h2>
          <p>These terms are governed by the laws of India. Courts at the city of our registered office have exclusive jurisdiction.</p>
          <h2>10. Contact</h2>
          <p>Questions about these terms: {contactLine(b)}.</p>
        </div>
      )}
    </Shell>
  )
}

export function Privacy() {
  return (
    <Shell title="Privacy policy" updated>
      {(b) => (
        <div className="prose">
          <h2>What we collect</h2>
          <ul>
            <li><b>Account details:</b> company name, GSTINs, admin names and email addresses, employee names, codes and mobile numbers.</li>
            <li><b>Bills you upload:</b> photos and PDFs of invoices and the details read from them (supplier, GSTIN, amounts, taxes).</li>
            <li><b>Usage and device data:</b> sign-in times, IP address, app version and push-notification tokens, used for security and support.</li>
            <li><b>Payments:</b> Razorpay order and payment IDs and amounts. Card, UPI and bank details are collected by Razorpay, not by us.</li>
          </ul>
          <h2>How we use it</h2>
          <p>To run the service (reading bills, approvals, reports and ITC matching), send one-time codes, receipts and renewal reminders, prevent fraud and abuse, and meet legal and tax obligations. We do not sell personal data or use it for advertising.</p>
          <h2>Service providers</h2>
          <p>We use trusted processors to operate the service: cloud hosting and database providers, file storage, email and SMS delivery, push notifications, AI document reading, GSTIN verification, error monitoring and Razorpay for payments. They process data only on our instructions.</p>
          <h2>Retention</h2>
          <p>Company data is kept while the account exists and for as long as required by tax law. When a company deletes its account, its bills and personal data are removed from the live system and from backups within 30 days, except records we must keep by law (for example payment invoices).</p>
          <h2>Security</h2>
          <p>Data is encrypted in transit (HTTPS), passwords are hashed, access is limited by role and company, and backups are taken regularly.</p>
          <h2>Your rights</h2>
          <p>You can access and correct your data in the console, export it, or ask us to delete it. Under the Digital Personal Data Protection Act, 2023 you may also withdraw consent or raise a grievance with us.</p>
          <h2>Grievance officer</h2>
          <p>{b.legalName}{b.address ? `, ${b.address}` : ''}. Email {contactLine(b)}. We acknowledge complaints within 48 hours and resolve them within 30 days.</p>
        </div>
      )}
    </Shell>
  )
}

export function RefundPolicy() {
  return (
    <Shell title="Refund & cancellation policy" updated>
      {(b) => (
        <div className="prose">
          <h2>Free trial first</h2>
          <p>Every company gets a {b.trialDays}-day free trial with full features, so you can evaluate {b.name} before paying.</p>
          <h2>Cancellation</h2>
          <p>Subscriptions are prepaid and do not renew automatically — nothing is charged unless you choose to renew. To stop using the service, simply do not renew; access continues until the end of the paid period.</p>
          <h2>Refunds</h2>
          <ul>
            <li><b>Duplicate or failed payments:</b> if you were charged twice, or money was debited but your subscription was not extended, we refund the extra amount in full.</li>
            <li><b>Within 7 days of a first paid purchase:</b> if the service does not work for you, write to us within 7 days of the payment for a full refund.</li>
            <li>Other than the above, fees for a period already started are not refundable.</li>
          </ul>
          <h2>How to request</h2>
          <p>Email {contactLine(b)} with your company name and the Razorpay payment ID from your receipt. Approved refunds are initiated within 2 business days and reach your original payment method within 5–7 business days, depending on your bank.</p>
        </div>
      )}
    </Shell>
  )
}

export function ShippingPolicy() {
  return (
    <Shell title="Delivery policy" updated>
      {(b) => (
        <div className="prose">
          <h2>Digital service — nothing is shipped</h2>
          <p>{b.name} is an online software service. No physical goods are shipped.</p>
          <h2>Delivery</h2>
          <p>Your subscription is activated instantly after a successful payment and the tax invoice is emailed to the paying admin. The web console is available in any modern browser, and the employee and admin apps are installed from the links provided by your company.</p>
          <p>If your subscription is not active within 30 minutes of payment, contact {contactLine(b)} and we will fix it the same business day.</p>
        </div>
      )}
    </Shell>
  )
}
