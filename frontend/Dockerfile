# ---- deps ----
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# ---- test: used by docker-compose.test.yml (Jenkins "Unit tests" stage) ----
# Reports (lcov for SonarQube, JUnit for Jenkins) are written to /app/reports
FROM deps AS test
COPY . .
CMD ["npm", "run", "test:ci"]

# ---- build ----
FROM deps AS build
COPY . .
RUN npm run build

# ---- runtime: default (last) stage ----
FROM nginx:1.27-alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
