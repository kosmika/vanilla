# Windows host-side init script for the dev container.
# PowerShell equivalent of setup-host.sh for native Windows (non-WSL2) users.
# Run manually: powershell -ExecutionPolicy Bypass -File .devcontainer\setup-host.ps1
#Requires -Version 5.1

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptDir

$NginxCertsDir = Join-Path $ProjectRoot "docker\images\nginx\certs"
$PhpCertsDir = Join-Path $ProjectRoot "docker\images\php\certs"

$Hostnames = @(
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

# ------------------------------------------------------------------
# 1. Docker network
# ------------------------------------------------------------------
function Ensure-Network {
    $networks = docker network ls --format "{{.Name}}" 2>$null
    if ($networks -contains "vanilla-network") {
        Write-Host "[network] vanilla-network already exists."
    }
    else {
        Write-Host "[network] Creating vanilla-network..."
        docker network create -d bridge vanilla-network
    }
}

# ------------------------------------------------------------------
# 2. SSL certificate generation
# ------------------------------------------------------------------
function Generate-SignedCert {
    param([string]$CertsDir, [string]$Name, [string]$CN)

    Write-Host "[certs]   Generating certificate for $Name..."
    openssl genrsa -out "$CertsDir\$Name.key" 2048 2>&1 | Out-Null

    openssl req -new `
        -key "$CertsDir\$Name.key" `
        -subj "/C=US/ST=Dev/L=Dev/O=Vanilla Dev/CN=$CN" `
        -out "$CertsDir\$Name.csr" 2>&1 | Out-Null

    $ExtContent = @"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CN
"@
    $ExtFile = "$CertsDir\$Name.ext"
    Set-Content -Path $ExtFile -Value $ExtContent

    openssl x509 -req `
        -in "$CertsDir\$Name.csr" `
        -CA "$CertsDir\ca.crt" `
        -CAkey "$CertsDir\ca.key" `
        -CAcreateserial `
        -out "$CertsDir\$Name.crt" `
        -days 825 `
        -sha256 `
        -extfile $ExtFile 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to sign certificate for $Name" }

    Remove-Item -Force "$CertsDir\$Name.csr", "$CertsDir\$Name.ext" -ErrorAction SilentlyContinue
}

function Generate-Certs {
    if (Test-Path "$NginxCertsDir\ca.crt") {
        Write-Host "[certs] Certificates already exist - skipping generation."
        return
    }

    Write-Host "[certs] Generating SSL certificates..."
    New-Item -ItemType Directory -Force -Path $NginxCertsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $PhpCertsDir | Out-Null

    # Root CA
    openssl genrsa -out "$NginxCertsDir\ca.key" 4096 2>&1 | Out-Null
    openssl req -x509 -new -nodes `
        -key "$NginxCertsDir\ca.key" `
        -sha256 -days 3650 `
        -subj "/C=US/ST=Dev/L=Dev/O=Vanilla Dev/CN=Dev Certificate Authority" `
        -out "$NginxCertsDir\ca.crt" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to generate Root CA" }

    Generate-SignedCert -CertsDir $NginxCertsDir -Name "vanilla.local" -CN "vanilla.local"
    Generate-SignedCert -CertsDir $NginxCertsDir -Name "wildcard.vanilla.local" -CN "*.vanilla.local"

    Copy-Item "$NginxCertsDir\ca.crt" -Destination $PhpCertsDir
    Copy-Item "$NginxCertsDir\vanilla.local.crt" -Destination $PhpCertsDir
    Copy-Item "$NginxCertsDir\wildcard.vanilla.local.crt" -Destination $PhpCertsDir

    Write-Host "[certs] Certificates generated successfully."
}

# ------------------------------------------------------------------
# 3. Trust CA certificate
# ------------------------------------------------------------------
function Trust-CA {
    $CaCrt = "$NginxCertsDir\ca.crt"

    # Compare the thumbprint of the CA on disk with what is in the cert store.
    # If they differ (or no entry exists), remove the stale entry and add the new one
    # so that a regenerated CA is always applied rather than silently skipped.
    $diskThumbprint = (Get-FileHash $CaCrt -Algorithm SHA1).Hash

    $storeThumbprint = $null
    try {
        $storeCert = Get-ChildItem Cert:\LocalMachine\Root |
            Where-Object { $_.Subject -match "Dev Certificate Authority" } |
            Select-Object -First 1
        if ($storeCert) {
            $storeThumbprint = $storeCert.Thumbprint
        }
    } catch {}

    if ($storeThumbprint -and $diskThumbprint -eq $storeThumbprint) {
        Write-Host "[certs] CA already trusted in Windows certificate store."
        return
    }

    if ($storeThumbprint) {
        Write-Host "[certs] CA fingerprint changed — removing stale entry from Windows certificate store..."
        Start-Process certutil -ArgumentList "-delstore", "Root", "Dev Certificate Authority" -Verb RunAs -Wait
    }

    Write-Host "[certs] Adding CA to Windows certificate store (requires elevation)..."
    Start-Process certutil -ArgumentList "-addstore", "-f", "ROOT", $CaCrt -Verb RunAs -Wait
    Write-Host "[certs] CA trusted."
}

# ------------------------------------------------------------------
# 4. Hosts file
# ------------------------------------------------------------------
function Ensure-Hosts {
    $HostsFile = "C:\Windows\System32\drivers\etc\hosts"
    $content = Get-Content $HostsFile -Raw -ErrorAction SilentlyContinue
    $missing = @()

    foreach ($hostname in $Hostnames) {
        foreach ($ip in @("127.0.0.1", "::1")) {
            $entry = "$ip $hostname # Added by vnla docker"
            if ($content -notmatch [regex]::Escape($entry)) {
                $missing += $entry
            }
        }
    }

    if ($missing.Count -eq 0) {
        Write-Host "[hosts] All host entries present."
        return
    }

    Write-Host "[hosts] Adding $($missing.Count) missing entries (requires elevation)..."
    $additions = $missing -join "`n"

    $script = "Add-Content -Path '$HostsFile' -Value `"``n$additions`""
    Start-Process powershell -ArgumentList "-Command", $script -Verb RunAs -Wait
    Write-Host "[hosts] Hosts file updated."
}

# ------------------------------------------------------------------
# 5. Start infrastructure services
# ------------------------------------------------------------------
function Start-Infra {
    $running = docker ps --format "{{.Names}}" 2>$null
    if ($running -contains "nginx") {
        Write-Host "[infra] Infrastructure containers already running - skipping."
        return
    }

    Write-Host "[infra] Starting infrastructure services..."
    $env:WWWUSER = "1000"
    $env:WWWGROUP = "1000"
    docker compose `
        -f "$ProjectRoot\docker\docker-compose.yml" `
        -f "$ProjectRoot\docker\docker-compose.nginx.yml" `
        -f "$ProjectRoot\docker\docker-compose.database.yml" `
        up --build -d
    Write-Host "[infra] Infrastructure services started."
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
Write-Host "=== Vanilla Dev Container: Host Setup (Windows) ==="
Write-Host ""

# Detect the docker group GID from WSL2 if available, otherwise default to 999.
try {
    $dockerGid = (wsl.exe getent group docker 2>$null) -replace "^.*:(\d+)$", '$1'
    if (-not $dockerGid) { $dockerGid = "999" }
} catch {
    $dockerGid = "999"
}
$env:DOCKER_GID = $dockerGid
Write-Host "[docker] Docker group GID: $dockerGid"

# Write .devcontainer\.env so docker compose picks up the correct UID/GID for
# this machine. WSL2 users whose UID is not 1000 need this to avoid EACCES
# errors caused by www-data being set to the wrong UID inside the container.
$envContent = @"
WWWUSER=1000
WWWGROUP=1000
DOCKER_GID=$dockerGid
"@
Set-Content -Path "$ScriptDir\.env" -Value $envContent
Write-Host "[env] Wrote .devcontainer\.env (WWWUSER=1000 WWWGROUP=1000 DOCKER_GID=$dockerGid)"

Ensure-Network
Generate-Certs
Trust-CA
Ensure-Hosts
Start-Infra

Write-Host ""
Write-Host "=== Host setup complete ==="
