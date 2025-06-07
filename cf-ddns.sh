set -euo pipefail

if [[ -f ".env" ]]; then
  source .env
fi

: "${CF_API_TOKEN:?Need CF_API_TOKEN in env or .env}"
: "${CF_RECORD_TYPES:?Need CF_RECORD_TYPES in env or .env}"

if [[ -n "${CF_ZONE_NAME:-}" && -n "${CF_SUBDOMAINS:-}" ]]; then
    ZONE_CONFIGS=("${CF_ZONE_NAME}:${CF_SUBDOMAINS}")
elif [[ -n "${CF_ZONE_CONFIGS:-}" ]]; then
    read -r -a ZONE_CONFIGS <<< "$CF_ZONE_CONFIGS"
else
    echo "Error: Either CF_ZONE_NAME+CF_SUBDOMAINS or CF_ZONE_CONFIGS must be set" >&2
    exit 1
fi

for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Error: $cmd is required" >&2
    exit 1
  }
done

CF_API_BASE="https://api.cloudflare.com/client/v4"

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

declare -A ZONE_IDS
declare -A ZONE_SUBDOMAINS

for config in "${ZONE_CONFIGS[@]}"; do
    if [[ ! "$config" =~ ^([^:]+):(.+)$ ]]; then
        echo "Error: Invalid zone config format '$config'. Expected format: 'zone_name:subdomain1,subdomain2,...'" >&2
        exit 1
    fi
    
    zone_name="${BASH_REMATCH[1]}"
    subdomains_str="${BASH_REMATCH[2]}"
    
    zone_id=$(
        curl -s \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            "${CF_API_BASE}/zones?name=${zone_name}" \
            | jq -r '.result[0].id'
    )
    
    if [[ -z "$zone_id" || "$zone_id" == "null" ]]; then
        echo "Error: could not fetch zone ID for ${zone_name}" >&2
        exit 1
    fi
    
    ZONE_IDS["$zone_name"]="$zone_id"
    ZONE_SUBDOMAINS["$zone_name"]="$subdomains_str"
    echo "Configured zone: $zone_name (ID: $zone_id)"
done

while true; do
  echo "===== $(date) Running DDNS updater ====="
  
  IPV4=$(curl -4 -s https://ifconfig.co 2>/dev/null || echo "")
  if [[ -n "$IPV4" ]]; then
    echo "Current IPv4: $IPV4"
  else
    echo "No IPv4 connectivity available"
  fi
  
  IPV6=$(curl -6 -s https://ifconfig.co 2>/dev/null || echo "")
  if [[ -n "$IPV6" ]]; then
    echo "Current IPv6: $IPV6"
  else
    echo "No IPv6 connectivity available"
  fi
  echo

  for zone_name in "${!ZONE_IDS[@]}"; do
    zone_id="${ZONE_IDS[$zone_name]}"
    subdomains_str="${ZONE_SUBDOMAINS[$zone_name]}"
    
    if [[ "$subdomains_str" == *","* ]]; then
        IFS=',' read -r -a subdomains <<< "$subdomains_str"
    else
        read -r -a subdomains <<< "$subdomains_str"
    fi
    
    echo "Processing zone: $zone_name"
    
    for sub in "${subdomains[@]}"; do
      sub=$(echo "$sub" | xargs)
      fqdn="${sub}.${zone_name}"
      
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
            "${CF_API_BASE}/zones/${zone_id}/dns_records?type=${type}&name=${fqdn}"
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
            "${CF_API_BASE}/zones/${zone_id}/dns_records" | jq
        elif [[ "$REC_IP" != "$NEW_IP" ]]; then
          echo "-> Updating $type record for $fqdn: $REC_IP → $NEW_IP"
          curl -s -X PATCH \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"${type}\",\"name\":\"${fqdn}\",\
\"content\":\"${NEW_IP}\",\"proxied\":false}" \
            "${CF_API_BASE}/zones/${zone_id}/dns_records/${REC_ID}" | jq
        else
          echo "-> $type record for $fqdn is already up to date"
        fi
      done
    done
    echo
  done

  echo "Sleeping for 1 hour..."
  sleep 3600
done
