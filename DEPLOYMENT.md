# Deploy to Render (go live)

One website serves **Super Admin**, **Admin Portal**, and **Client Capture** (role-based). One API backs all of them. Push this repo, then connect Render.

## 1. Push to GitHub

Repo: https://github.com/Raama0202/GST-Spike.git

## 2. Create services on Render

### Option A — Blueprint (recommended)

1. Open [Render Dashboard](https://dashboard.render.com) → **New** → **Blueprint**
2. Connect `Raama0202/GST-Spike`
3. Apply `render.yaml`
4. Fill **sync: false** env vars (see below)

### Option B — Manual

**API (Web Service)**
- Runtime: Node
- Build: `npm install && npm --workspace @gst-suite/api run build`
- Start: `npm --workspace @gst-suite/api run start`
- Health check: `/api/health`
- Add **Persistent Disk**: mount `/var/data/uploads` (bill images)

**Web (Static Site)**
- Build: `npm install && npm --workspace @gst-suite/web run build`
- Publish directory: `apps/web/dist`

## 3. Environment variables

### API (`gst-spike-api`)

| Key | Value |
|-----|--------|
| `NODE_ENV` | `production` |
| `USE_MEMORY_MONGO` | `false` |
| `AUTO_SEED_DEMO` | `true` (first boot; set `false` later) |
| `UPLOAD_DIR` | `/var/data/uploads` |
| `MONGODB_URI` | your Atlas `mongodb://...` or `mongodb+srv://...` string |
| `JWT_SECRET` | long random string |
| `WEB_ORIGIN` | your static site URL, e.g. `https://gst-spike-web.onrender.com` |
| `GEMINI_API_KEY` | Google AI Studio key |
| `GEMINI_MODEL` | `gemini-2.0-flash` |
| `FAST2SMS_API_KEY` | optional |
| `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` | optional (test/live) |

### Web (`gst-spike-web`) — **must be set before build**

| Key | Value |
|-----|--------|
| `VITE_API_URL` | `https://YOUR-API-SERVICE.onrender.com/api` |
| `VITE_ASSET_URL` | `https://YOUR-API-SERVICE.onrender.com` |
| `VITE_ENABLE_DEMO_FALLBACK` | `false` |

After the API gets its public URL, set the two Vite vars and **Clear build cache + Redeploy** the static site.

## 4. Atlas network

In MongoDB Atlas → **Network Access** → allow `0.0.0.0/0` (or Render outbound IPs) so the API can connect.

## 5. Smoke test

1. `https://YOUR-API.onrender.com/api/health` → `{ "ok": true }`
2. Open the static site → login
3. Demo (if seeded): `super@gst.local` / `owner@gst.local` / `worker@gst.local` — password `demo123`
4. Worker uploads a bill → Admin **Open bill** → zoom/verify

## Product surfaces (one site)

| URL path | Who |
|----------|-----|
| `/login` | Everyone |
| `/super-admin` | Platform / subscriptions |
| `/admin` | Company GST ops + bill verify |
| `/client` | Field capture (upload only) |

Android WebView can point at the same static site URL for the “client app”.

## Notes

- Free Render web services **sleep** after idle; first request can take ~30–60s.
- Bill images need the API **disk**; without it, images are lost on redeploy.
- Never commit `.env` — secrets live only in Render.
