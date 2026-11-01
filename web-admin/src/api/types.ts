export interface Items<T> {
  items: T[]
}

export interface Page<T> extends Items<T> {
  total: number
  page: number
  pageSize: number
}

export interface Seats {
  used: number
  limit: number | null
}

export type PaymentStatus = 'created' | 'authorized' | 'paid' | 'failed' | 'refunded'

export interface PaymentOrder {
  id: string
  companyId: string
  companyName: string | null
  planCode: string
  seats: number
  months: number
  amount: number | string
  currency: string
  status: PaymentStatus
  providerOrderId: string
  providerPaymentId: string | null
  failureReason: string | null
  /** Set once the payment succeeds; the GST invoice is at /admin/billing/orders/{id}/invoice. */
  invoiceNumber?: string | null
  refundedAmount?: number | string
  createdAt: string
  paidAt: string | null
}

export interface PaymentsPage extends Page<PaymentOrder> {
  paymentsEnabled: boolean
  totals?: { paidInr: number | string; paidCount: number; refundedInr?: number | string; netInr?: number | string }
}

export interface BillingPlan {
  code: string
  name: string
  monthlyPriceInr: number | string
  maxEmployees: number | null
  features: Record<string, unknown>
  /** False for free / trial plans, which can't be bought online. */
  purchasable?: boolean
}

export interface BillingOverview {
  paymentsEnabled: boolean
  keyId: string | null
  taxPercent: number
  /** False while Razorpay test keys are configured: no real money moves. */
  liveMode?: boolean
  businessName?: string
  activeEmployees?: number
  subscription: {
    planCode: string
    seats: number
    startsAt: string
    endsAt: string
    status: string
    isActive: boolean
  } | null
  plans: BillingPlan[]
  orders: PaymentOrder[]
}

export interface CheckoutOrder {
  id: string
  orderId: string
  keyId: string
  amountPaise: number
  currency: string
  quote: { subtotal: number | string; tax: number | string; taxPercent: number; total: number | string; amountPaise: number }
  companyName: string | null
  prefillEmail: string | null
  description: string
}

export interface BusinessInfo {
  name: string
  legalName: string
  gstin: string | null
  address: string | null
  email: string | null
  phone: string | null
  taxPercent: number
  paymentsEnabled: boolean
  trialDays: number
}

export interface PublicPlans {
  items: Omit<BillingPlan, 'purchasable'>[]
  taxPercent: number
}

interface InvoiceParty {
  name: string | null
  legalName: string | null
  gstin: string | null
  address?: string | null
  email?: string | null
  phone?: string | null
  state: { code: string; name: string } | null
}

export interface BillingInvoice {
  orderId: string
  number: string
  issuedAt: string
  title: string
  seller: InvoiceParty
  buyer: InvoiceParty
  placeOfSupply: { code: string; name: string } | null
  reverseCharge: boolean
  lines: { description: string; sac: string; quantity: number; unit: string; rate: number | string; amount: number | string }[]
  subtotal: number | string
  taxPercent: number | string
  cgst: number | string
  sgst: number | string
  igst: number | string
  total: number | string
  amountInWords: string
  payment: { method: string | null; orderId: string | null; paymentId: string | null; paidAt: string | null }
  refundedAmount: number | string
}

export interface AnnouncementSummary {
  title: string
  body: string
  createdAt: string
  recipients: number
  read: number
}

export type CompanyStatus = 'pending' | 'active' | 'suspended'

export interface Company {
  id: string
  name: string
  legalName: string | null
  gstin: string | null
  industry: string | null
  status: CompanyStatus
  activationCode: string
  createdAt: string
  planCode?: string | null
  planName?: string | null
  seats?: number | null
  subscriptionStatus?: string | null
  endsAt?: string | null
  employeeCount?: number | null
  lastActivityAt?: string | null
  adminEmail?: string | null
}

export interface CompanySubscription {
  planCode: string
  planName: string | null
  seats: number
  status: string
  startsAt: string | null
  endsAt: string
}

export interface CompanyDetail {
  company: Company
  admins: { id: string; email: string; name: string | null; isActive: boolean; createdAt: string }[]
  subscription: CompanySubscription | null
  usage: {
    employees: number
    activeEmployees: number
    invoices: number
    invoices30d: number
    pendingInvoices: number
    lastActivityAt: string | null
  }
  payments: PaymentOrder[]
}

export interface Plan {
  id: string
  code: string
  name: string
  monthlyPriceInr: number
  maxEmployees: number | null
  features: Record<string, unknown>
  subscriberCount?: number
}

export interface PlatformMetrics {
  companies: { all: number; active: number; pending: number; suspended: number }
  signups30d: number
  employeesActive: number
  invoices30d: number
  mrrInr: number | string
  revenue30dInr: number | string
  revenueTotalInr: number | string
  expiringSoon: { companyId: string; companyName: string; planCode: string; endsAt: string }[]
  daily: { date: string; signups: number; invoices: number; revenueInr: number | string }[]
}

export interface Dashboard {
  pendingCount: number
  todayUploads: number
  approvedCount: number
  rejectedCount: number
  returnedCount: number
  approvedAmount?: number | string
  pendingAmount?: number | string
  daily?: { date: string; count: number; amount: number | string }[]
  topCategories?: { name: string; count: number; amount: number | string }[]
  seats?: Seats
}

export type ApprovalStatus = 'pending' | 'approved' | 'rejected' | 'returned'

export interface InvoiceFields {
  vendorName?: string | null
  gstin?: string | null
  invoiceNumber?: string | null
  invoiceDate?: string | null
  taxableValue?: number | string | null
  cgst?: number | string | null
  sgst?: number | string | null
  igst?: number | string | null
  discount?: number | string | null
  netAmount?: number | string | null
  expenseCategoryName?: string | null
  supplierPhone?: string | null
  supplierEmail?: string | null
  remarks?: string | null
  [key: string]: unknown
}

export interface Invoice {
  id: string
  localIdempotencyKey: string
  approvalStatus: ApprovalStatus
  adminRemarks: string | null
  editedData: InvoiceFields
  ocrData: InvoiceFields
  imageUrl: string | null
  thumbnailUrl: string | null
  uploadedAt: string
  invoiceNumber: string | null
  /** YYYY-MM-DD; the field the date filter works on. */
  invoiceDate: string | null
  gstin: string | null
  vendorName: string | null
  netAmount: number | string | null
  vendorIsCompany?: boolean
  employeeId?: string | null
  employeeName?: string | null
  employeeCode?: string | null
  branchId?: string | null
  branchName?: string | null
  categoryId?: string | null
  categoryName?: string | null
  reviewedAt?: string | null
  updatedAt?: string | null
  /** Supplier GSTIN status from the GST portal; null until the background check finishes. */
  gstinCheck?: GstinCheck | null
}

export type GstinStatus = 'active' | 'cancelled' | 'suspended' | 'inactive' | 'not_found' | 'invalid_format' | 'unverified'

export interface GstinCheck {
  status: GstinStatus
  legalName: string | null
  tradeName: string | null
  cancellationDate: string | null
  message: string | null
  checkedAt: string | null
}

/** GET /gstin/{gstin}; the public sign-up check returns a subset. */
export interface GstinLookup {
  gstin: string
  formatValid: boolean
  status: GstinStatus
  statusText?: string | null
  legalName: string | null
  tradeName: string | null
  registrationDate?: string | null
  cancellationDate?: string | null
  taxpayerType?: string | null
  constitution?: string | null
  address?: string | null
  stateName: string | null
  einvoiceEnabled?: boolean | null
  liveCheck: boolean
  checkedAt?: string | null
  message: string | null
  error?: string | null
}

export type InvoiceAction = 'uploaded' | 'approved' | 'rejected' | 'returned' | 'resubmitted' | 'edited'

export interface InvoiceHistoryEntry {
  action: InvoiceAction | string
  remarks: string | null
  byName: string | null
  at: string
}

export interface InvoiceDetail extends Invoice {
  originalImageUrl: string | null
  latitude: number | string | null
  longitude: number | string | null
  deviceId: string | null
  history?: InvoiceHistoryEntry[]
}

export interface Employee {
  id: string
  name: string
  mobile: string
  email: string | null
  employeeCode: string
  companyId: string
  branchId: string | null
  branchName: string | null
  isActive: boolean
  createdAt?: string
}

export interface EmployeesPage extends Page<Employee> {
  seats?: Seats
}

export interface NamedResource {
  id: string
  name: string
  code: string | null
  parentId: string | null
  sortOrder: number
  isActive: boolean
}

/** GET returns snake_case; PATCH takes the camelCase equivalents. */
export interface CompanySettings {
  id: string
  name: string
  legal_name: string | null
  gstin: string | null
  additional_gstins: string[]
  name_aliases: string[]
  state_code: string | null
  industry: string | null
  logo_url: string | null
  primary_color_hex: string | null
  requires_gps: boolean
  duplicate_check_enabled: boolean
  min_ocr_confidence_warn: number
  features_json: Record<string, unknown>
  status: CompanyStatus
  activation_code: string
  gstin_check?: { status: GstinStatus; legal_name: string | null; trade_name: string | null; message: string | null; checked_at: string | null } | null
}

export interface CompanySettingsUpdate {
  name?: string
  legalName?: string | null
  gstin?: string | null
  additionalGstins?: string[]
  nameAliases?: string[]
  industry?: string | null
  logoUrl?: string | null
  primaryColorHex?: string | null
  requiresGps?: boolean
  duplicateCheckEnabled?: boolean
  minOcrConfidenceWarn?: number
}

export interface NotificationItem {
  id: string
  type: string
  title: string
  body: string
  createdAt: string
  read: boolean
  invoiceServerId: string | null
}

export interface AuditEntry {
  id: string
  action: string
  targetType: string | null
  targetId: string | null
  summary: string | null
  actorEmail: string | null
  actorRole: string | null
  createdAt: string
  companyId?: string | null
  companyName?: string | null
}

export type ItcStatus =
  | 'matched'
  | 'mismatch'
  | 'missing_in_2b'
  | 'missing_in_books'
  | string

export interface ItcMatch {
  id: string
  status: ItcStatus
  amountDelta: number | null
  notes: string | null
  invoice: {
    id: string
    vendorName: string | null
    gstin: string | null
    invoiceNumber: string | null
    invoiceDate: string | null
    netAmount: number | null
    supplierPhone: string | null
    supplierEmail: string | null
  } | null
  portalRow: {
    id: string
    supplierName: string | null
    supplierGstin: string | null
    invoiceNumber: string | null
    invoiceDate: string | null
    netAmount: number | null
  } | null
}

export interface ItcImport {
  id: string
  period: string
  returnType: string
  source: string
  status: string
  rowCount: number
  originalFilename: string | null
  errorMessage: string | null
  createdAt: string
}

export interface Reminder {
  id: string
  invoiceId: string
  matchId: string | null
  channel: string
  status: string
  contactPhone: string | null
  contactEmail: string | null
  messagePreview: string | null
  called: boolean
  promisedBy: string | null
  resolvedAt: string | null
  createdAt: string
}

export interface ReminderResult {
  id: string
  channel: string
  status: string
  message: string
  whatsappUrl: string | null
  mailtoUrl: string | null
  invoiceId: string
  matchId: string | null
  contactPhone: string | null
  contactEmail: string | null
}
