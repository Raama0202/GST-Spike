# Backend API Contract (v1)

Base URL: `{API_BASE_URL}` (example `https://api.gstexpenses.app/v1`)

All authenticated requests require:

```
Authorization: Bearer <access_token>
X-Company-Id: <company_uuid>
X-Device-Id: <stable_device_uuid>
```

## Auth

### POST `/auth/otp/request`

```json
{ "mobile": "9876543210" }
```

Response `204` or `{ "ok": true }`

### POST `/auth/otp/verify`

```json
{ "mobile": "9876543210", "otp": "123456" }
```

```json
{
  "accessToken": "...",
  "refreshToken": "...",
  "expiresIn": 3600,
  "employee": {
    "id": "emp_uuid",
    "name": "Ravi Kumar",
    "mobile": "9876543210",
    "employeeCode": "EMP014",
    "companyId": "co_uuid",
    "companyName": "Acme Construction",
    "branchId": "br_uuid",
    "branchName": "Site A"
  }
}
```

### POST `/auth/token/refresh`

```json
{ "refreshToken": "..." }
```

Returns new `accessToken` + `refreshToken`.

### POST `/auth/logout`

Invalidates refresh token. `204`.

### GET `/employees/me`

Returns current employee profile (same shape as `employee` above).

## Company config

### GET `/company/config`

```json
{
  "companyId": "co_uuid",
  "companyName": "Acme Construction",
  "industry": "Construction",
  "logoUrl": "https://...",
  "primaryColorHex": "0B5FFF",
  "requiresGps": false,
  "duplicateCheckEnabled": true,
  "minOcrConfidenceWarn": 0.55,
  "features": { "galleryImport": true, "remarksRequired": false },
  "gstinLiveCheck": true,
  "categories": [
    { "id": "cat1", "name": "Cement", "parentId": null, "sortOrder": 1 }
  ],
  "branches": [
    { "id": "br1", "name": "Site A", "code": "A" }
  ],
  "updatedAt": "2026-07-30T10:00:00Z"
}
```

`gstinLiveCheck` is true when a GST portal provider is configured on the server.

## GSTIN verification

### GET `/gstin/{gstin}`

Any signed-in user. Checks the GSTIN with the GST portal through the configured GSP
(cached for 24 hours). Admins may pass `?refresh=true` to skip the cache.

```json
{
  "gstin": "29AFSPB9500E1Z7",
  "formatValid": true,
  "status": "active",
  "statusText": "Active",
  "legalName": "Vicky Private Limited",
  "tradeName": "Vicky Traders",
  "registrationDate": "2019-10-18",
  "cancellationDate": null,
  "taxpayerType": "Regular",
  "constitution": "Private Limited Company",
  "address": "26, Whitefield Main Road, Bangalore, Bengaluru Urban, Karnataka - 560048",
  "stateCode": "29",
  "stateName": "Karnataka",
  "einvoiceEnabled": false,
  "liveCheck": true,
  "source": "sandbox",
  "checkedAt": "2026-11-01T10:00:00Z",
  "message": "Active on the GST portal"
}
```

`status` is one of `active`, `cancelled`, `suspended`, `inactive`, `not_found`,
`invalid_format` or `unverified` (no provider configured, or the provider failed; `liveCheck`
is then false and `error` may be present).

### POST `/public/gstin/check`

No sign-in; 10 requests per hour per IP. Body `{ "gstin": "..." }`. Returns only `gstin`,
`formatValid`, `status`, `legalName`, `tradeName`, `stateName`, `liveCheck` and `message`.
Used by the firm sign-up form.

### GET `/gstin/status`

`{ "liveCheck": true, "provider": "sandbox" }`

Invoices carry `gstinCheck` (`status`, `legalName`, `tradeName`, `cancellationDate`,
`message`, `checkedAt`) once the background check finishes; admins filter with `gstinStatus`
(`problem` = cancelled, suspended, inactive, not found or invalid) and re-check with
`POST /admin/invoices/{id}/verify-gstin`.

## Invoices

`netAmount` is the **invoice value**: the full amount of the bill including GST. The JSON
key keeps its original name so existing app versions and stored invoices stay compatible.

### POST `/invoices/duplicate-check`

```json
{
  "invoiceNumber": "INV-1",
  "gstin": "29ABCDE1234F1Z5",
  "invoiceDate": "2026-03-15",
  "netAmount": 11700.0
}
```

```json
{ "isDuplicate": true, "matchedInvoiceId": "inv_uuid", "message": "Possible duplicate" }
```

### POST `/invoices/upload` (multipart)

Fields:

| Field | Type | Notes |
|---|---|---|
| `idempotencyKey` | text | Client local UUID — required |
| `payload` | text/json | Invoice JSON body |
| `original` | file | Original JPEG |
| `compressed` | file | ≤ ~1MB JPEG |
| `thumbnail` | file | Small JPEG |

`payload` JSON:

```json
{
  "branchId": "br_uuid",
  "deviceId": "dev_uuid",
  "latitude": 12.97,
  "longitude": 77.59,
  "ocrConfidence": 0.82,
  "ocrData": { "...": "..." },
  "editedData": { "...": "..." },
  "duplicateOverride": false
}
```

Response:

```json
{
  "id": "inv_uuid",
  "approvalStatus": "pending",
  "uploadedAt": "2026-07-30T10:05:00Z"
}
```

Replaying the same `idempotencyKey` must return the same invoice (no duplicate rows).

### GET `/invoices/mine`

Query: `?page=1&pageSize=50&updatedSince=ISO8601`

```json
{
  "items": [
    {
      "id": "inv_uuid",
      "localIdempotencyKey": "local-uuid",
      "approvalStatus": "approved",
      "adminRemarks": null,
      "editedData": {},
      "ocrData": {},
      "imageUrl": "https://...",
      "thumbnailUrl": "https://...",
      "uploadedAt": "..."
    }
  ]
}
```

## Notifications

### GET `/notifications`

```json
{
  "items": [
    {
      "id": "n1",
      "type": "billApproved",
      "title": "Bill approved",
      "body": "INV-1 approved",
      "createdAt": "...",
      "read": false,
      "invoiceServerId": "inv_uuid"
    }
  ]
}
```

Notification `type` enum: `billApproved`, `billRejected`, `billReturned`, `companyAnnouncement`, `appUpdate`

### POST `/notifications/read`

```json
{ "ids": ["n1", "n2"] }
```

## Devices

### POST `/devices/register`

```json
{ "deviceId": "...", "platform": "android", "appVersion": "1.0.0", "fcmToken": null }
```

## Public (no auth)

### GET `/public/business`

Seller details for the pricing, contact and policy pages:
`{ name, legalName, gstin, address, email, phone, taxPercent, paymentsEnabled, trialDays }`.
`taxPercent` is 0 when the platform has no GSTIN.

### GET `/public/plans`

`{ items: [{ code, name, monthlyPriceInr, maxEmployees, features }], taxPercent }`. Paid plans only.

## Subscription billing (company admin, web console)

### GET `/admin/billing`

`{ paymentsEnabled, keyId, taxPercent, liveMode, businessName, activeEmployees, subscription, plans, orders }`.
`liveMode` is false while Razorpay test keys are configured. Each order has
`invoiceNumber` (once paid) and `refundedAmount`; `status` is `created | authorized | paid | failed | refunded`.

### POST `/admin/billing/orders` → 201

Body `{ planCode, seats, months }`. Returns `{ id, orderId, keyId, amountPaise, currency, quote, companyName, prefillEmail, description }`
for Razorpay Checkout (`orderId` is the Razorpay order ID, `id` the internal one).

### POST `/admin/billing/verify`

Body `{ razorpayOrderId, razorpayPaymentId, razorpaySignature }` from the Checkout handler.
Verifies the signature, extends the subscription once and issues the invoice.

### GET `/admin/billing/orders/{id}/invoice`

GST invoice for a paid order (409 before payment, 404 for another company's order):
`{ number, issuedAt, title, seller, buyer, placeOfSupply, reverseCharge, lines[{ description, sac, quantity, unit, rate, amount }],
subtotal, taxPercent, cgst, sgst, igst, total, amountInWords, payment{ method, orderId, paymentId, paidAt }, refundedAmount }`.
`title` is "Tax Invoice" when GST is charged, otherwise "Invoice". The super admin equivalent is
`GET /super/payments/{id}/invoice`; `GET /super/payments` totals include `refundedInr` and `netInr`.

### POST `/payments/razorpay/webhook`

Razorpay → API, verified with `X-Razorpay-Signature`. Handles `payment.captured`, `order.paid`
(credit, refused when the amount differs from the order), `payment.failed`, and
`refund.processed` / `refund.created` / `payment.refunded` (records the refunded amount; full refunds set status `refunded`).
Duplicate deliveries (same `X-Razorpay-Event-Id`) are ignored.

## Error shape

```json
{ "message": "Human readable", "code": "OPTIONAL_CODE" }
```

HTTP: `400` validation, `401` auth, `403` tenant, `409` conflict, `429` rate limit, `5xx` server.
