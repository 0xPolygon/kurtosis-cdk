FROM node:22-bookworm-slim
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm ci --include=dev
COPY . .
RUN npm run build
RUN apt-get update && apt-get install -y nginx
# Allow Kurtosis to override the config file
RUN mkdir -p /kurtosis_config \
    && touch /kurtosis_config/config.json \
    && touch /kurtosis_config/nginx.conf \
    && rm -f /usr/src/app/src/config/config.json \
    && rm -f /etc/nginx/nginx.conf \
    && ln -s /kurtosis_config/config.json /usr/src/app/src/config/config.json \
    && ln -s /kurtosis_config/nginx.conf /etc/nginx/nginx.conf
ENV NODE_ENV=development
EXPOSE 60444
CMD nginx -g 'daemon off;' & npm run build && npm run preview -- --port 800 --host 0.0.0.0
