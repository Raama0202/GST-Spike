# SUPER_ADMIN_MASTER.md

> Version 1.0 (Foundation Specification)

# Purpose

Central SaaS administration portal for managing all customer companies, subscriptions, licenses, feature flags, application versions, and operational health.

## Objectives

- Manage customers
- Generate and renew subscription licenses
- Control application updates
- Monitor platform usage
- Manage support and audit logs
- Prepare for payment gateway integration

## Technology

- React + TypeScript
- Vite
- Tailwind CSS
- shadcn/ui
- NestJS backend (shared)
- MongoDB Atlas
- JWT + Role-Based Access Control

## Super Admin Modules

### Dashboard
- Active companies
- Active subscriptions
- Expiring subscriptions
- Invoice volume
- OCR success rate
- Reminder statistics
- System health

### Company Management
- Create company
- Suspend/activate
- Branch management
- View usage
- Storage statistics

### Subscription Management
- Generate unique license code
- Activate/deactivate
- Renewal history
- Expiry reminders
- Future payment status

Example License:
COMPANY-2026-ABCD-1234

### User Administration
- View all users
- Reset passwords
- Lock/unlock accounts
- Force logout

### Feature Flags
Enable/disable features per company:
- OCR
- GST reconciliation
- WhatsApp connector
- SMS connector
- Reports
- AI validation

### Version Management
- Publish latest client version
- Publish latest admin portal version
- Force minimum supported version
- Release notes

### Support
- Ticket overview (future)
- Remote diagnostics metadata
- Error logs
- Sync failures

### Audit Logs
Track:
- Login
- License changes
- User changes
- Company status
- Feature flag updates

### Notifications
- Global announcements
- Maintenance windows
- Update notices

## Shared Backend Responsibilities

- Authentication
- Licensing
- Company isolation (multi-tenant)
- API gateway
- Notification service
- Audit service

## Payment (Future Ready)

Abstract payment interface supporting:
- Razorpay
- Cashfree
- Stripe
- Manual renewal

## Deployment

Frontend:
- Vercel / Cloudflare Pages

Backend:
- Railway / Render / Fly.io

Database:
- MongoDB Atlas

## Security

- RBAC
- HTTPS
- JWT
- Refresh tokens
- Audit trails
- Rate limiting

---
This foundation specification defines the Super Admin portal. The complete production version will expand each module with UI flows, database mappings, APIs, operational procedures, billing lifecycle, monitoring, backup, disaster recovery, and deployment details.
