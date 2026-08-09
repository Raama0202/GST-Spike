FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/package.json
RUN npm ci --workspace=@gst-suite/api --include-workspace-root

FROM deps AS build
COPY apps/api apps/api
RUN npm --workspace=@gst-suite/api run build

FROM node:22-alpine AS runner
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/package.json
RUN npm ci --workspace=@gst-suite/api --omit=dev --include-workspace-root
COPY --from=build /app/apps/api/dist apps/api/dist
WORKDIR /app/apps/api
ENV UPLOAD_DIR=/var/data/uploads
EXPOSE 4000
CMD ["node", "dist/main.js"]
