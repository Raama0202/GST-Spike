export interface Items<T> {
  items: T[]
}

export interface Page<T> extends Items<T> {
  total: number
  page: number
  pageSize: number
}

export type PaymentStatus = 'created' | 'authorized' | 'paid' | 'failed'

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
  createdAt: string
  paidAt: string | null
}

export interface BillingOverview {
  paymentsEnabled: boolean
  keyId: string | null
  taxPercent: number
  subscription: {
    planCode: string
    seats: number
    startsAt: string
    endsAt: string
    status: string
    isActive: boolean
  } | null
  plans: { code: string; name: string; monthlyPriceInr: number | string; maxEmployees: number | null; features: Record<string, unknown> }[]
  orders: PaymentOrder[]
}

export interface CheckoutOrder {
  orderId: string
  keyId: string
  amountPaise: number
  currency: string
  quote: { subtotal: number | string; tax: number | string; taxPercent: number; total: number | string; amountPaise: number }
  companyName: string | null
  prefillEmail: string | null
  description: string
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
  industry: string | null
  status: CompanyStatus
  activationCode: string
  createdAt: string
}

export interface Plan {
  id: string
  code: string
  name: string
  monthlyPriceInr: number
  maxEmployees: number | null
  features: Record<string, unknown>
}

export interface Dashboard {
  pendingCount: number
  todayUploads: number
  approvedCount: number
  rejectedCount: number
  returnedCount: number
}

export type ApprovalStatus = 'pending' | 'approved' | 'rejected' | 'returned'

export interface InvoiceFields {
  vendorName?: string | null
  gstin?: string | null
  invoiceNumber?: string | null
  invoiceDate?: string | null
  taxableValue?: number | null
  cgst?: number | null
  sgst?: number | null
  igst?: number | null
  discount?: number | null
  netAmount?: number | null
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
  gstin: string | null
  vendorName: string | null
  netAmount: number | string | null
}

export interface InvoiceDetail extends Invoice {
  originalImageUrl: string | null
  latitude: number | string | null
  longitude: number | string | null
  deviceId: string | null
}

export interface Employee {
  id: string
  name: string
  mobile: string
  employeeCode: string
  companyId: string
  branchId: string | null
  branchName: string | null
  isActive: boolean
}

export interface NamedResource {
  id: string
  name: string
  code: string | null
  parentId: string | null
  sortOrder: number
  isActive: boolean
}

export interface CompanySettings {
  id: string
  name: string
  industry: string | null
  logo_url: string | null
  primary_color_hex: string | null
  requires_gps: boolean
  duplicate_check_enabled: boolean
  min_ocr_confidence_warn: number
  features_json: Record<string, unknown>
  status: CompanyStatus
  activation_code: string
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
}
