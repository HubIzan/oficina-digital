# Oficina Digital · © 2026 Izan Trompeta (HubIzan) · Licencia MIT · https://github.com/HubIzan/oficina-digital
FROM node:26-slim
ARG VERSION
RUN npm install --global --no-audit --no-fund "vercel@${VERSION}"
ENTRYPOINT ["vercel"]
