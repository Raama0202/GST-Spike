import { Link } from 'react-router-dom'

export const PUBLIC_LINKS = [
  ['/pricing', 'Pricing'],
  ['/contact', 'Contact us'],
  ['/terms', 'Terms & conditions'],
  ['/privacy', 'Privacy policy'],
  ['/refund-policy', 'Refund & cancellation'],
  ['/shipping-policy', 'Delivery policy'],
] as const

export function PublicFooterLinks() {
  return (
    <nav className="public-links" aria-label="Policies">
      {PUBLIC_LINKS.map(([to, label]) => <Link key={to} to={to}>{label}</Link>)}
    </nav>
  )
}
