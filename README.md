# GST Spike

GST SaaS suite: **Super Admin** + **Admin Portal** + **Client Capture** (one web app) and a NestJS API with Atlas MongoDB + Gemini bill extraction.

## Local

```bash
npm install
copy apps\api\.env.example apps\api\.env
# fill MONGODB_URI, GEMINI_API_KEY, etc.
npm run dev
```

- Web: http://localhost:5173  
- API: http://localhost:4000/api/health  

## Production (Render)

See [DEPLOYMENT.md](./DEPLOYMENT.md). Blueprint: [render.yaml](./render.yaml).

GitHub: https://github.com/Raama0202/GST-Spike.git

## Demo logins (when `AUTO_SEED_DEMO=true`)

Password `demo123`:

- `super@gst.local` — platform  
- `owner@gst.local` — company admin  
- `worker@gst.local` — bill capture  
