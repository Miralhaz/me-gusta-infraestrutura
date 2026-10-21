# =============================================================================
# MeGusta Frontend - Multi-stage (Vite/React) + Nginx
# =============================================================================
# Build context: <repo>/me-gusta-frontend  (o codigo do front esta nessa subpasta)
# O nginx.conf (deste repo de infraestrutura) faz o reverse proxy de /api para
# o servico "backend:8080" na rede overlay do Swarm, evitando que o navegador
# precise resolver "localhost" ou um hostname interno.
# =============================================================================
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
# npm ci é reproduzível, mas falha (EUSAGE) se o package-lock.json do repo estiver
# fora de sincronia com o package.json (ex.: "Missing: @emnapi/core... from lock file").
# Fallback para npm install, que resolve e instala o que faltar sem quebrar o build.
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund
COPY . .

# A aplicacao fixa baseURL="http://localhost:8080" em src/provider/api.js.
# No navegador isso aponta para a maquina do usuario (nao funciona em producao).
# Reescrevemos qualquer ocorrencia para o prefixo relativo "/api", que sera
# servido pelo nginx do frontend e encaminhado ao backend via proxy.
RUN grep -rl "http://localhost:8080" src | while IFS= read -r f; do sed -i 's|http://localhost:8080|/api|g' "$f"; done

ARG VITE_API_URL=/api
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build

FROM nginx:alpine
# nginx.conf com fallback SPA (try_files) + proxy /api -> backend
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
