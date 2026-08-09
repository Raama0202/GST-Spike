# ADMIN_PORTAL_MASTER.md

> Version 1.0 (Foundation Specification)

# Purpose

React-based web portal for business owners and Chartered Accountants to monitor invoices, reconcile GST, manage reminders, and administer company users.

## Tech Stack

- React + TypeScript + Vite
- Tailwind CSS + shadcn/ui
- TanStack Query
- Zustand
- NestJS backend
- MongoDB Atlas
- JWT Authentication
- Socket.IO

## Roles

- Owner
- Chartered Accountant
- Accountant
- Supervisor (read-only optional)

## Modules

### Dashboard
- Today's uploads
- Pending OCR reviews
- GST summary
- Missing invoices
- Reminder queue
- Savings analytics

### Invoice Management
- Search/filter
- OCR confidence
- Image preview
- Edit fields
- Duplicate detection
- Export Excel/PDF

### GST Reconciliation
- Import GSTR-2A / GSTR-2B (Excel/CSV initially)
- Compare against uploaded invoices
- Match status:
  - Matched
  - Uploaded by client only
  - GST portal only
  - Amount mismatch

### Reminder Engine

Queue reminders for unmatched supplier invoices.

Providers (pluggable):
- WhatsApp Business API (future)
- Desktop automation connector (optional)
- SMS gateway
- Email

Track:
- Pending
- Sent
- Failed
- Manual follow-up required

### Company Management
- Branches
- Users
- Roles
- Activity logs

### Subscription
- Activate company code
- View expiry
- Renew (payment integration later)

### Reports
- Monthly GST recovered
- Missed claim trends
- User productivity
- Supplier performance

## Backend APIs (summary)

POST /auth/login
GET /dashboard
GET /invoices
PUT /invoice/{id}
POST /gst/import
POST /reminders/send
GET /reports
GET /subscription

## Security

- RBAC
- HTTPS
- Audit logs
- Refresh tokens
- Rate limiting

## Deployment

Frontend:
- Vercel/Cloudflare Pages

Backend:
- Railway/Render/Fly.io

Database:
- MongoDB Atlas

Storage:
- Cloudinary or equivalent

---
This is the foundation specification. The production document will expand every module with screen-by-screen UI, API contracts, workflows, validation rules, database mappings, architecture diagrams, testing, deployment, and operational guidance.
