# ---- deps ----
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# ---- test: used by Jenkins (docker build --target test) ----
FROM deps AS test
COPY . .
RUN npm test

# ---- build ----
FROM deps AS build
COPY . .
RUN npm run build

# ---- runtime: default (last) stage ----
FROM nginx:1.27-alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
