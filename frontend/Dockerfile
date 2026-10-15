# ---- deps ----
FROM node:24-alpine@sha256:44fce696f38ba8c987c4db89954051000bbd05ffd8d8659ba15ed4a8602e937f AS deps
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
FROM nginx:stable-alpine@sha256:ed84151ed2d47ef93c0939eb9b9754c6990db6092cd2081e11988a47a83d47ea AS runtime
ARG APP_BUILD=dev
ARG APP_REVISION=unknown
LABEL org.opencontainers.image.title="Sprout frontend" \
      org.opencontainers.image.version=${APP_BUILD} \
      org.opencontainers.image.revision=${APP_REVISION}
COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/dist /usr/share/nginx/html
USER nginx
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
  CMD wget -qO- http://127.0.0.1:8080/api/health || exit 1
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
