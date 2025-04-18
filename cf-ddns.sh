set -euo pipefail

if [[ -f ".env" ]]; then
  export $(grep -v '^#' .env | xargs)
fi

: "${CF_API_TOKEN:?Need CF_API_TOKEN in env or .env}"
: "${CF_ZONE_NAME:?Need CF_ZONE_NAME in env or .env}"
: "${CF_SUBDOMAINS:?Need CF_SUBDOMAINS in env or .env}"
: "${CF_RECORD_TYPES:?Need CF_RECORD_TYPES in env or .env}"

for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Error: $cmd is required" >&2
    exit 1
  }
done

CF_API_BASE="https://api.cloudflare.com/client/v4"

read -r -a SUBDOMAINS <<< "$CF_SUBDOMAINS"

read -r -a RECORD_TYPES <<< "$CF_RECORD_TYPES"

for rt in "${RECORD_TYPES[@]}"; do
    if [[ "$rt" != "A" && "$rt" != "AAAA" ]]; then
        echo "Error: Invalid record type '$rt' found in CF_RECORD_TYPES. Only 'A' and 'AAAA' are allowed." >&2
        exit 1
    fi
done

if [[ ${#RECORD_TYPES[@]} -eq 0 ]]; then
    echo "Error: CF_RECORD_TYPES cannot be empty. Must contain 'A' and/or 'AAAA'." >&2
    exit 1
fi

ZONE_ID=$(
  curl -s \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${CF_API_BASE}/zones?name=${CF_ZONE_NAME}" \
    | jq -r '.result[0].id'
)
if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
  echo "Error: could not fetch zone ID for ${CF_ZONE_NAME}" >&2
  exit 1
fi

while true; do
  echo "===== $(date) Running DDNS updater ====="
  IPV4=$(curl -4 -s https://ifconfig.co)
  IPV6=$(curl -6 -s https://ifconfig.co)
  echo "Current IPv4: $IPV4"
  echo "Current IPv6: $IPV6"
  echo

  for sub in "${SUBDOMAINS[@]}"; do
    fqdn="${sub}.${CF_ZONE_NAME}"
    for type in "${RECORD_TYPES[@]}"; do
      if [[ "$type" == "A" ]]; then
          if [[ -z "$IPV4" ]]; then echo "Skipping A record for $fqdn (no IPv4)"; continue; fi
          NEW_IP="$IPV4"
      elif [[ "$type" == "AAAA" ]]; then
          if [[ -z "$IPV6" ]]; then echo "Skipping AAAA record for $fqdn (no IPv6)"; continue; fi
          NEW_IP="$IPV6"
      fi

      resp=$(
        curl -s \
          -H "Authorization: Bearer ${CF_API_TOKEN}" \
          -H "Content-Type: application/json" \
          "${CF_API_BASE}/zones/${ZONE_ID}/dns_records?type=${type}&name=${fqdn}"
      )
      REC_ID=$(echo "$resp" | jq -r '.result[0].id // empty')
      REC_IP=$(echo "$resp" | jq -r '.result[0].content // empty')

      if [[ -z "$REC_ID" ]]; then
        echo "-> Creating $type record for $fqdn → $NEW_IP"
        curl -s -X POST \
          -H "Authorization: Bearer ${CF_API_TOKEN}" \
          -H "Content-Type: application/json" \
          --data "{\"type\":\"${type}\",\"name\":\"${fqdn}\",\
\"content\":\"${NEW_IP}\",\"proxied\":false}" \
          "${CF_API_BASE}/zones/${ZONE_ID}/dns_records" | jq
      elif [[ "$REC_IP" != "$NEW_IP" ]]; then
        echo "-> Updating $type record for $fqdn: $REC_IP → $NEW_IP"
        curl -s -X PATCH \
          -H "Authorization: Bearer ${CF_API_TOKEN}" \
          -H "Content-Type: application/json" \
          --data "{\"type\":\"${type}\",\"name\":\"${fqdn}\",\
\"content\":\"${NEW_IP}\",\"proxied\":false}" \
          "${CF_API_BASE}/zones/${ZONE_ID}/dns_records/${REC_ID}" | jq
      else
        echo "-> $type record for $fqdn is already up to date"
      fi
    done
    echo
  done

  echo "Sleeping for 1 hour..."
  sleep 3600
done
