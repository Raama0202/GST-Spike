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
  "categories": [
    { "id": "cat1", "name": "Cement", "parentId": null, "sortOrder": 1 }
  ],
  "branches": [
    { "id": "br1", "name": "Site A", "code": "A" }
  ],
  "updatedAt": "2026-07-30T10:00:00Z"
}
```

## Invoices

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

## Error shape

```json
{ "message": "Human readable", "code": "OPTIONAL_CODE" }
```

HTTP: `400` validation, `401` auth, `403` tenant, `409` conflict, `429` rate limit, `5xx` server.
