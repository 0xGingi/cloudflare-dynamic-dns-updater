# Cloudflare Dynamic DNS Updater

This script automatically updates Cloudflare A and AAAA DNS records for specified subdomains to match the host's current public IPv4 and IPv6 addresses. It runs continuously, checking for IP changes every hour.

## How it Works

The script fetches the current public IPv4 and IPv6 addresses using `ifconfig.co`. It then uses the Cloudflare API to:

1.  Get the Zone ID for the specified `CF_ZONE_NAME`.
2.  For each subdomain listed in the `SUBDOMAINS` array within `cf-ddns.sh`:
    *   Query the existing A and AAAA records.
    *   If a record doesn't exist, create it with the current IP.
    *   If a record exists but the IP is different, update it.
3.  Sleep for one hour before repeating the process.

## Requirements

*   `docker`
*   `docker compose`
*   A Cloudflare API Token with `Zone:Read` and `DNS:Edit` permissions.
*   Your Cloudflare Zone Name.

## Setup

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/0xgingi/cloudflare-dynamic-dns-updater
    cd cloudflare-dynamic-dns-updater
    ```
2.  **Create an environment file:**
    Copy the example file:
    ```bash
    cp env.example .env
    ```
    Edit `.env` and add your Cloudflare API Token and Zone Name:
    ```dotenv
    # Cloudflare API Token (generate from Cloudflare dashboard)
    # Ensure the token has Zone:Read and DNS:Edit permissions
    CF_API_TOKEN=YOUR_CLOUDFLARE_API_TOKEN

    # Your Cloudflare Zone Name (e.g., example.com)
    CF_ZONE_NAME=yourdomain.com

    # Space-separated list of subdomains to update (e.g., "www blog api")
    CF_SUBDOMAINS="sub1 sub2 sub3"

    # Space-separated list of record types to update (e.g., "A AAAA", "A", "AAAA")
    CF_RECORD_TYPES="A AAAA"
    ```

## Run

1.  **Build the Docker image:**
    ```bash
    docker compose build
    ```
2.  **Run the container:**
    ```bash
    docker compose up -d
    ```
