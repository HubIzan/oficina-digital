FROM node:26-slim AS compilar
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY index.html isla.html vite.config.js ./
COPY src ./src
RUN npx vite build

FROM scratch AS salida
COPY --from=compilar /app/dist /
