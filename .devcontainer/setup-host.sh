#!/usr/bin/env bash
# Host-side init script for the dev container. Mirrors the logic in
# cli/src/Docker/HostValidator.php but without requiring PHP on the host.
# Supports macOS, Linux, and WSL2. Run automatically via devcontainer initializeCommand.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NGINX_CERTS_DIR="$PROJECT_ROOT/docker/images/nginx/certs"
PHP_CERTS_DIR="$PROJECT_ROOT/docker/images/php/certs"

HOSTNAMES=(
    "database"
    "memcached"
    "vanilla.local"
    "dev.vanilla.local"
    "sso.vanilla.local"
    "e2e-tests.vanilla.local"
    "embed.vanilla.local"
    "advanced-embed.vanilla.local"
    "modern-embed.vanilla.local"
    "modern-embed-hub.vanilla.local"
    "queue.vanilla.local"
    "elastic.vanilla.local"
    "kibana.vanilla.local"
    "search.vanilla.local"
    "frontend.vanilla.local"
    "files.vanilla.local"
    "files-api.vanilla.local"
    "management.vanilla.local"
    "imgproxy.vanilla.local"
    "clickhouse.vanilla.local"
    "mail.vanilla.local"
)

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl2"
    else
        echo "linux"
    fi
}

# ------------------------------------------------------------------
# 1. Docker network
# ------------------------------------------------------------------
ensure_network() {
    if docker network ls --format '{{.Name}}' | grep -qx "vanilla-network"; then
        echo "[network] vanilla-network already exists."
    else
        echo "[network] Creating vanilla-network..."
        docker network create -d bridge vanilla-network
    fi
}

# ------------------------------------------------------------------
# 2. SSL certificate generation (mirrors HostValidator::generateCerts)
# ------------------------------------------------------------------
generate_signed_cert() {
    local certs_dir="$1" name="$2" cn="$3"

    echo "[certs]   Generating certificate for $name..."
    openssl genrsa -out "$certs_dir/$name.key" 2048 2>/dev/null

    openssl req -new \
        -key "$certs_dir/$name.key" \
        -subj "/C=US/ST=Dev/L=Dev/O=Vanilla Dev/CN=$cn" \
        -out "$certs_dir/$name.csr" 2>/dev/null

    local ext_file="$certs_dir/$name.ext"
    cat > "$ext_file" <<EXTEOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $cn
EXTEOF

    openssl x509 -req \
        -in "$certs_dir/$name.csr" \
        -CA "$certs_dir/ca.crt" \
        -CAkey "$certs_dir/ca.key" \
        -CAcreateserial \
        -out "$certs_dir/$name.crt" \
        -days 825 \
        -sha256 \
        -extfile "$ext_file" 2>/dev/null

    rm -f "$certs_dir/$name.csr" "$certs_dir/$name.ext"
}

generate_certs() {
    if [[ -f "$NGINX_CERTS_DIR/ca.crt" ]]; then
        echo "[certs] Certificates already exist — skipping generation."
        return
    fi

    echo "[certs] Generating SSL certificates..."
    mkdir -p "$NGINX_CERTS_DIR" "$PHP_CERTS_DIR"

    # Root CA
    openssl genrsa -out "$NGINX_CERTS_DIR/ca.key" 4096 2>/dev/null
    openssl req -x509 -new -nodes \
        -key "$NGINX_CERTS_DIR/ca.key" \
        -sha256 -days 3650 \
        -subj "/C=US/ST=Dev/L=Dev/O=Vanilla Dev/CN=Dev Certificate Authority" \
        -out "$NGINX_CERTS_DIR/ca.crt" 2>/dev/null

    generate_signed_cert "$NGINX_CERTS_DIR" "vanilla.local" "vanilla.local"
    generate_signed_cert "$NGINX_CERTS_DIR" "wildcard.vanilla.local" "*.vanilla.local"

    cp "$NGINX_CERTS_DIR/ca.crt"                    "$PHP_CERTS_DIR/"
    cp "$NGINX_CERTS_DIR/vanilla.local.crt"          "$PHP_CERTS_DIR/"
    cp "$NGINX_CERTS_DIR/wildcard.vanilla.local.crt" "$PHP_CERTS_DIR/"

    echo "[certs] Certificates generated successfully."
}

# ------------------------------------------------------------------
# 3. Trust CA certificate on the host OS
# ------------------------------------------------------------------
trust_ca_macos() {
    local ca_crt="$NGINX_CERTS_DIR/ca.crt"

    # Compare fingerprints so that a regenerated CA (same CN, different key)
    # always replaces the stale entry rather than being silently skipped.
    local disk_fp keychain_fp
    disk_fp="$(openssl x509 -in "$ca_crt" -noout -fingerprint -sha256 2>/dev/null)"
    keychain_fp="$(security find-certificate -c "Dev Certificate Authority" -p 2>/dev/null \
        | openssl x509 -noout -fingerprint -sha256 2>/dev/null)"

    if [[ -n "$keychain_fp" && "$disk_fp" == "$keychain_fp" ]]; then
        echo "[certs] CA already trusted in macOS Keychain."
        return
    fi

    if [[ -n "$keychain_fp" ]]; then
        echo "[certs] CA fingerprint changed — removing stale entry from macOS Keychain..."
        sudo security delete-certificate -c "Dev Certificate Authority" \
            /Library/Keychains/System.keychain 2>/dev/null || true
    fi

    echo "[certs] Adding CA to macOS Keychain (you may be prompted for your password)..."
    sudo security add-trusted-cert -d -r trustRoot -p ssl \
        -k /Library/Keychains/System.keychain "$ca_crt"
    echo "[certs] CA trusted."
}

trust_ca_linux() {
    local ca_crt="$NGINX_CERTS_DIR/ca.crt"
    local dest="/usr/local/share/ca-certificates/vanilla-dev-ca.crt"

    # Use cmp to detect when the CA on disk differs from what is installed so
    # that a regenerated CA always replaces the stale entry.
    if [[ -f "$dest" ]] && cmp -s "$ca_crt" "$dest"; then
        echo "[certs] CA already in Linux CA store."
        return
    fi

    if [[ -f "$dest" ]]; then
        echo "[certs] CA changed — updating Linux CA store (you may be prompted for your password)..."
    else
        echo "[certs] Adding CA to Linux CA store (you may be prompted for your password)..."
    fi

    sudo cp "$ca_crt" "$dest"
    sudo update-ca-certificates
    echo "[certs] CA trusted."
}

trust_ca_wsl2() {
    trust_ca_linux

    local ca_crt="$NGINX_CERTS_DIR/ca.crt"
    local win_cert
    win_cert="$(wslpath -w "$ca_crt")"
    echo "[certs] Updating CA in Windows certificate store (you may see a UAC prompt)..."
    # Delete any existing entry first to avoid stale duplicates, then add the new one.
    powershell.exe -Command "Start-Process certutil -ArgumentList '-delstore','Root','Dev Certificate Authority' -Verb RunAs -Wait" 2>/dev/null || true
    powershell.exe -Command "Start-Process certutil -ArgumentList '-addstore','-f','ROOT','$win_cert' -Verb RunAs" 2>/dev/null || \
        echo "[certs] WARNING: Could not add CA to Windows store. You may need to run certutil manually."
}

trust_ca() {
    local os
    os="$(detect_os)"
    case "$os" in
        macos) trust_ca_macos ;;
        wsl2)  trust_ca_wsl2 ;;
        linux) trust_ca_linux ;;
    esac
}

# ------------------------------------------------------------------
# 4. Hosts file
# ------------------------------------------------------------------
ensure_hosts_unix() {
    local hosts_file="/etc/hosts"
    local missing=()

    for hostname in "${HOSTNAMES[@]}"; do
        for ip in "127.0.0.1" "::1"; do
            local entry="$ip $hostname # Added by vnla docker"
            if ! grep -qF "$entry" "$hosts_file"; then
                missing+=("$entry")
            fi
        done
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "[hosts] All host entries present."
        return
    fi

    echo "[hosts] Adding ${#missing[@]} missing entries (you may be prompted for your password)..."
    local additions
    additions="$(printf '%s\n' "${missing[@]}")"
    echo "$additions" | sudo tee -a "$hosts_file" >/dev/null
    echo "[hosts] Hosts file updated."
}

ensure_hosts_wsl2() {
    ensure_hosts_unix

    local win_hosts
    win_hosts="$(wslpath 'C:\Windows\System32\drivers\etc\hosts')"
    local missing=()

    for hostname in "${HOSTNAMES[@]}"; do
        for ip in "127.0.0.1" "::1"; do
            local entry="$ip $hostname # Added by vnla docker"
            if ! grep -qF "$entry" "$win_hosts" 2>/dev/null; then
                missing+=("$entry")
            fi
        done
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "[hosts] Windows hosts file already up to date."
        return
    fi

    echo "[hosts] Updating Windows hosts file (you may see a UAC prompt)..."
    local additions
    additions="$(printf '%s\n' "${missing[@]}")"
    powershell.exe -Command "Start-Process powershell -ArgumentList '-Command',\"Add-Content 'C:\\Windows\\System32\\drivers\\etc\\hosts' '\`n$additions'\" -Verb RunAs" 2>/dev/null || \
        echo "[hosts] WARNING: Could not update Windows hosts file automatically. Please add entries manually."
}

ensure_hosts() {
    local os
    os="$(detect_os)"
    case "$os" in
        wsl2)  ensure_hosts_wsl2 ;;
        *)     ensure_hosts_unix ;;
    esac
}

# ------------------------------------------------------------------
# 5. Start infrastructure services (skip if already running)
# ------------------------------------------------------------------
start_infra() {
    if docker ps --format '{{.Names}}' | grep -qx "nginx"; then
        echo "[infra] Infrastructure containers already running — skipping."
        return
    fi

    echo "[infra] Starting infrastructure services..."
    WWWUSER="$(id -u)" WWWGROUP="$(id -g)" \
        docker compose \
            -f "$PROJECT_ROOT/docker/docker-compose.yml" \
            -f "$PROJECT_ROOT/docker/docker-compose.nginx.yml" \
            -f "$PROJECT_ROOT/docker/docker-compose.database.yml" \
            up --build -d
    echo "[infra] Infrastructure services started."
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
main() {
    echo "=== Vanilla Dev Container: Host Setup ==="
    echo "OS detected: $(detect_os)"
    echo ""

    # Export DOCKER_GID so docker-compose passes it through to the Dockerfile
    # ARG, letting www-data join the correct docker group for socket access.
    DOCKER_GID="$(getent group docker 2>/dev/null | cut -d: -f3 || echo 999)"
    export DOCKER_GID
    echo "[docker] Docker group GID: $DOCKER_GID"

    # Write .devcontainer/.env so docker compose picks up the correct UID/GID
    # for this machine. Without this, the Dockerfile defaults to 1000 and
    # www-data will not match the host user, causing EACCES errors on the
    # bind-mounted workspace for users whose UID is not 1000.
    cat > "$SCRIPT_DIR/.env" <<EOF
WWWUSER=$(id -u)
WWWGROUP=$(id -g)
DOCKER_GID=$DOCKER_GID
EOF
    echo "[env] Wrote .devcontainer/.env (WWWUSER=$(id -u) WWWGROUP=$(id -g) DOCKER_GID=$DOCKER_GID)"

    ensure_network
    generate_certs
    trust_ca
    ensure_hosts
    start_infra

    echo ""
    echo "=== Host setup complete ==="
}

main "$@"
