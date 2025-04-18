# Dockerfile
FROM alpine:3.21
RUN apk add --no-cache bash curl jq
WORKDIR /app
COPY cf-ddns.sh   /app/cf-ddns.sh
RUN chmod +x /app/cf-ddns.sh
ENTRYPOINT ["/bin/bash", "/app/cf-ddns.sh"]
