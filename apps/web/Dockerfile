FROM node:22-alpine AS build
WORKDIR /app
ARG VITE_API_URL
ARG VITE_ASSET_URL
ARG VITE_ENABLE_DEMO_FALLBACK=false
ENV VITE_API_URL=$VITE_API_URL
ENV VITE_ASSET_URL=$VITE_ASSET_URL
ENV VITE_ENABLE_DEMO_FALLBACK=$VITE_ENABLE_DEMO_FALLBACK
COPY package.json package-lock.json ./
COPY apps/web/package.json apps/web/package.json
RUN npm ci --workspace=@gst-suite/web --include-workspace-root
COPY apps/web apps/web
RUN npm --workspace=@gst-suite/web run build

FROM nginx:1.27-alpine AS runner
COPY apps/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/apps/web/dist /usr/share/nginx/html
EXPOSE 80
