FROM node:26-slim AS test
WORKDIR /app
COPY package.json sitio.config.json ./
COPY public ./public
COPY test ./test
RUN chmod -R a+rX /app
USER node
ENV SITIO_DIR=public
CMD ["node", "--test"]

FROM nginxinc/nginx-unprivileged:stable-alpine AS final
COPY public /usr/share/nginx/html
USER root
RUN chmod -R a+rX /usr/share/nginx/html
USER nginx
