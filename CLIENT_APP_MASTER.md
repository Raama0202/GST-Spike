# CLIENT_APP_MASTER.md

> **Version:** 1.0 (Foundation Specification)

## Purpose

Native Android application for workers, supervisors, and site staff to capture GST purchase invoices and synchronize them securely with the company's subscription.

## Primary Goals

- Capture invoices quickly.
- Extract GST fields using OCR.
- Work offline.
- Sync automatically.
- Minimize user effort.

## Technology

- Kotlin
- Jetpack Compose
- CameraX
- ML Kit OCR (on-device)
- Room Database
- WorkManager
- Retrofit
- Hilt
- Coil
- JWT Authentication

## User Roles

- Worker
- Supervisor
- Manager

## First Launch

1. Enter Subscription Code.
2. Validate with backend.
3. Device registration.
4. Login.
5. Sync master data.

## Dashboard

- Scan Bill
- Pending Sync
- History
- Search
- Profile

## Invoice Capture Flow

Camera
→ Auto crop
→ Perspective correction
→ Blur detection
→ OCR
→ AI parser (backend)
→ User verification
→ Save locally
→ Background sync

## Fields

Required:
- Company Name
- GSTIN
- Invoice Number
- Invoice Date
- Seller Phone
- Taxable Amount
- GST Amount
- Total Amount

Optional:
- HSN
- Items
- Notes
- Location

## OCR Rules

- Confidence score per field.
- Highlight uncertain fields.
- Validate GSTIN format.
- Prevent duplicate invoice uploads.

## Offline

Invoices remain in Room database until synced.

## API Summary

POST /auth/login

POST /subscription/activate

POST /invoice/upload

GET /invoice/history

GET /profile

## Security

- JWT
- HTTPS
- Encrypted local storage
- Device binding

## Folder Structure

app/
 core/
 data/
 domain/
 feature/auth
 feature/dashboard
 feature/camera
 feature/invoice
 feature/profile
 sync/
 ui/

## Future

- Voice notes
- Barcode reading
- PDF upload
- Multi-language

---

This is the foundation document. The complete production version will expand each section with detailed UI flows, API contracts, state diagrams, validation rules, testing, and implementation details.
