FROM node:26-slim
ARG VERSION
RUN npm install --global --no-audit --no-fund "vercel@${VERSION}"
ENTRYPOINT ["vercel"]
