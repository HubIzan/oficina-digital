# Construye con pnpm (version fija, sin scripts de instalacion salvo esbuild y sin versiones de menos de 7 dias).
FROM node:26-slim AS construir
RUN npm install --global --ignore-scripts pnpm@12.17.0
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY astro.config.mjs sitio.config.json tsconfig.json ./
COPY src ./src
COPY public ./public
RUN pnpm build

# Los tests miran el HTML final, sin red y sin node_modules.
FROM node:26-slim AS test
WORKDIR /app
COPY package.json sitio.config.json ./
COPY test ./test
COPY --from=construir /app/dist ./dist
RUN chmod -R a+rX /app
USER node
ENV SITIO_DIR=dist
CMD ["node", "--test"]

FROM nginxinc/nginx-unprivileged:stable-alpine AS final
COPY --from=construir /app/dist /usr/share/nginx/html
USER root
RUN chmod -R a+rX /usr/share/nginx/html
USER nginx
