# Dev Container Setup Guide

This guide walks you through setting up a local development environment for Vanilla using a [Dev Container](https://containers.dev/). The dev container gives you a fully configured workspace inside a Docker container — no need to install PHP, Node, or Composer on your machine.

## What you get

Once set up, you will have:

- A shell environment with PHP 8.3, Node.js, Yarn, and Composer — all pre-installed
- The Vanilla codebase mounted at `/srv/vanilla-repositories/vanilla` inside the container
- Infrastructure services (Nginx, MySQL, Memcached, PHP-FPM) running alongside your dev container
- HTTPS access to your local site at `https://vanilla.local/{YOUR-SITENAME}` from your host browser
- The ability to run `./cli/bin/vnla` commands, `composer`, `yarn`, and other tools inside the container

## Editor support

The dev container works with any tool that supports the [Dev Container spec](https://containers.dev/):

- **VS Code** — install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- **Cursor** — built-in support (look for "Reopen in Container" in the command palette)
- **JetBrains IDEs** — supported via the [Dev Containers plugin](https://www.jetbrains.com/help/idea/connect-to-devcontainer.html)
- **CLI only** — install the [devcontainer CLI](https://github.com/devcontainers/cli): `npm install -g @devcontainers/cli`

You can also use the dev container without an editor — see [CLI-only usage](#cli-only-usage) below.

## Step-by-step setup

### 1. Install prerequisites

You need the following installed on your host machine before continuing.

**macOS / Linux**

| Tool | Install link | Notes |
|------|-------------|-------|
| **Docker Desktop** | [docker.com/install](https://docs.docker.com/install/) | Required. On Linux you can use Docker Engine instead. |
| **Git** | [git-scm.com](https://git-scm.com/) | To clone the repository. |
| **OpenSSL** | Usually pre-installed | Run `openssl version` to check. |

**Windows**

WSL2 is required on Windows. The repository must live inside the WSL2 filesystem — the Windows NTFS filesystem does not support Unix file permissions (`chmod`) or cross-device hard links, both of which Yarn's workspace linking requires.

1. Open PowerShell as Administrator and install WSL2 with Ubuntu:

   ```powershell
   wsl --install -d Ubuntu
   ```

   If you prefer Alpine Linux:

   ```powershell
   wsl --install -d Alpine
   ```

   Restart your machine when prompted, then complete the initial Linux user setup in the new terminal window that opens.

2. Install [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/) and enable the WSL2 backend:
   - Open Docker Desktop → Settings → Resources → WSL Integration
   - Enable integration for your installed distro (e.g. Ubuntu)

3. Open your WSL2 terminal (Ubuntu or your chosen distro) and install OpenSSL (if not already present):

   ```bash
   # Ubuntu / Debian
   sudo apt-get update && sudo apt-get install -y openssl

   # Alpine
   apk add openssl
   ```

   Alternatively, OpenSSL is bundled with [Git for Windows](https://git-scm.com/downloads/win) or can be installed via `winget install OpenSSL` on the Windows side, which is used by the PowerShell fallback script.

### 2. Clone the repository

**macOS / Linux**

```bash
mkdir -p ~/vnla
cd ~/vnla
git clone <repository-url> vanilla
cd vanilla
```

**Windows (WSL2)**

Open your WSL2 terminal (Ubuntu or your chosen distro) and clone into the WSL2 filesystem — **not** into `/mnt/c/`:

```bash
mkdir -p ~/vnla
cd ~/vnla
git clone <repository-url> vanilla
cd vanilla
```

> Cloning to a path like `/mnt/c/Repos/...` will cause `EPERM`/`EXDEV` errors during `yarn install` and significant performance issues. Always use the Linux home directory (`~/vnla`).

### 3. Open in your editor

#### Install required extensions (VS Code only)

If you are using VS Code on Windows, install two extensions before continuing:

- **[WSL](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl)** — lets VS Code connect to and work inside your WSL2 environment. Without this, VS Code runs on the Windows side and cannot see the Linux filesystem correctly.
- **[Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)** — provides the "Reopen in Container" command that builds and attaches to the dev container.

Install both from the Extensions panel (`Ctrl+Shift+X`) by searching their names, or click the links above and press **Install**.

> Cursor has built-in support for both WSL and dev containers — no additional extensions are needed.

1. You should Restart Docker and your IDE
2. Via the terminal confirm things are wroking by typing wsl it might be a good idea to run sudo apt-get update as well
```
wsl
sudo apt-get update
```

#### Connect to WSL and open the project (Windows)

Once the extensions are installed, connect VS Code to your WSL2 environment:

1. Open the Command Palette (`Ctrl+Shift+P`) and run **WSL: Connect to WSL** (or click the `><` remote indicator in the bottom-left corner of the status bar and choose **Connect to WSL**).

2. A new VS Code window opens connected to your WSL distro. You will see the remote indicator change to something like **WSL: Ubuntu**.

3. Open a terminal inside VS Code (`Ctrl+`` ` ``) — this terminal runs inside Linux — and navigate to the project:

   ```bash
   cd ~/vnla/vanilla
   ```

4. Open the folder in VS Code from that terminal:

   ```bash
   code .
   ```

   Alternatively, use **File → Open Folder** and browse to `\\wsl.localhost\Ubuntu\home\<your-user>\vnla\vanilla`.

#### Build or rebuild the dev container

With the `vanilla` folder open, VS Code will detect `.devcontainer/devcontainer.json` and show a prompt:

> **"Reopen in Container"** — click this.

If the prompt does not appear, open the Command Palette (`Ctrl+Shift+P`) and run **Dev Containers: Reopen in Container**.

To force a full rebuild (e.g. after pulling changes to the `Dockerfile` or `docker-compose.devcontainer.yml`), use **Dev Containers: Rebuild and Reopen in Container** instead.

The first build takes several minutes. You can follow progress by clicking **Show Log** in the notification that appears in the bottom-right corner, or by watching the **Configuring** and **Dev Containers** terminal tabs that open automatically.

#### Password and access control prompts

During the host setup phase you may be asked for your password or see system access control prompts. These are expected — they are required to install the local SSL certificates so your browser can reach `https://vanilla.local` without a security warning.

- **macOS** — a `sudo` password prompt will appear in the terminal.
- **Windows (WSL2)** — you may see a UAC elevation dialog for the Windows certificate store and hosts file updates.

> Please note older versions of Vanilla and may contain expired certificates. You may be notified in your browser of choice that the local site is not secure.

#### Wait for post-create setup to finish

After the container starts, a terminal will open and run the post-create commands automatically:

```
composer install && yarn install && ./cli/bin/vnla install && ...
```

Wait for this to complete — you will see a final line such as:

```
Done. Press any key to close the terminal.
```

> If this process hangs without any further feedback for longer than 10 minutes. Try closing the dev container then rebuilding it.

Do **not** open a new terminal or run commands until this finishes.

If you run into an issue during the yarn install see: ### EACCES errors during `yarn install` in the devcontainer section below

<img width="785" height="506" alt="image" src="https://github.com/user-attachments/assets/653c6f7d-abcc-4067-acd6-4d94eb72a67b" />

After you complete the stes in ### EACCES errors during `yarn install` you will need to go back into docker and delete the dev container listed there and try again.

#### Open a new terminal and create your first site

Once the post-create setup is done, open a fresh terminal inside the container (`Ctrl+`` ` `` → **New Terminal**) and run:

```bash
./cli/bin/vnla spawn-site
```

Follow the interactive prompts to choose a base path for your site. When complete, you will be shown the URL, database name, and admin credentials for your new local site.

**macOS / Linux:** The steps are the same — open the `vanilla` folder in your editor. If your editor supports dev containers, it will detect `.devcontainer/devcontainer.json` and prompt you to **"Reopen in Container"**. If the prompt does not appear, open the command palette and search for **"Reopen in Container"**.

### 4. What happens automatically

When you reopen in the container, the following steps run in order:

1. **Host setup** (runs on your machine before the container starts):
   - Creates the `vanilla-network` Docker network
   - Generates SSL certificates for `*.vanilla.local` (if they don't already exist)
   - Adds the CA certificate to your OS trust store
   - Adds hostname entries to your hosts file
   - Starts infrastructure services (Nginx, MySQL, Memcached, PHP-FPM)

   **macOS / Linux:** `setup-host.sh` runs and may prompt for your password for `sudo` operations.

   **Windows (WSL2):** `setup-host.sh` auto-detects WSL2 and handles both the Linux-side and Windows-side hosts file and certificate store. You may see a UAC prompt for the Windows certificate and hosts file updates.

   If bash is not available (e.g. running from a native Windows context), the setup falls back to `setup-host.ps1`. To run it manually from an elevated PowerShell prompt:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .devcontainer\setup-host.ps1
   ```

2. **Container build** (first time only, takes a few minutes):
   - Builds the dev container image from `ghcr.io/vanilla/php:8.3`

3. **Post-create setup** (runs inside the container):
   - `composer install` — installs PHP dependencies
   - `yarn install` — installs JavaScript dependencies
   - `./cli/bin/vnla install` — adds `./cli/bin/vnla` to your shell `$PATH`
   - Creates symlinks for the Docker bootstrap files so PHP-FPM can route per-site requests correctly

The first run takes several minutes. Subsequent opens are much faster since Docker caches the image and only dependency installs run again.

### 5. Build the frontend

```bash
./cli/bin/vnla build
```

For active frontend development, use the dev build which watches for changes:

```bash
./cli/bin/vnla build --dev
```

### 6. Visit your site

Open your host browser and go to:

```
https://vanilla.local/{YOUR-SITENAME}
```

You should see your Vanilla site. The browser should trust the certificate (green padlock) because the CA was added to your OS trust store in step 4.

> **Troubleshooting:** If you see a certificate warning, the CA trust step may not have completed. See [Certificate troubleshooting](#certificate-issues) below.

## Day-to-day usage

### Starting the environment

Just open the project in your editor — it will automatically reopen in the container. The `initializeCommand` ensures infrastructure services are started.

### Stopping the environment

Close your editor, or run from the command palette: **"Dev Containers: Reopen Folder Locally"**.

To also stop the infrastructure containers, run on your host (or WSL2 shell):

```bash
cd ~/vnla/vanilla/docker
docker compose -f docker-compose.yml -f docker-compose.nginx.yml -f docker-compose.database.yml down
```

### Running commands

All commands should be run **inside the dev container** terminal, not on your host:

```bash
# PHP dependencies
composer install
composer require some/package

# JavaScript dependencies
yarn install

# Build frontend
./cli/bin/vnla build
./cli/bin/vnla build --dev

# Clear caches
./cli/bin/vnla clear-caches

# Spawn a new site
./cli/bin/vnla spawn-site
```

### Where is my code?

Inside the container, your code is at:

```
/srv/vanilla-repositories/vanilla
```

This is the same path used by all other containers (Nginx, PHP-FPM), so any file you edit is immediately available to the running site.

## CLI-only usage

If you prefer not to use an editor's dev container support, you can use the `devcontainer` CLI:

```bash
# Install the CLI (one time)
npm install -g @devcontainers/cli

# Start the dev container
cd ~/vnla/vanilla
devcontainer up --workspace-folder .

# Open a shell inside
devcontainer exec --workspace-folder . bash

# Stop
docker compose -f .devcontainer/docker-compose.devcontainer.yml down
```

## Troubleshooting

### Certificate issues

#### `ERR_CERT_AUTHORITY_INVALID` — browser does not trust the certificate

This error means the browser's CA trust store is out of date. It typically happens after certs are regenerated (the new certs are signed by a new CA, but the old CA is still the one the browser trusts). Follow these steps in order:

**1. Stop the devcontainer**

Command palette → **"Dev Containers: Reopen Folder Locally"**, or close the editor window entirely.

**2. Close all browser windows**

The browser caches the certificate store per session — a full restart is required for trust store changes to take effect.

**3. Stop the infrastructure containers and delete the nginx image**

Open a plain WSL2 terminal (or your host terminal on macOS/Linux) and run:

```bash
cd ~/vnla/vanilla/docker
docker compose -f docker-compose.yml -f docker-compose.nginx.yml -f docker-compose.database.yml down
docker image rm vanilla-nginx 2>/dev/null || true
```

Removing the nginx image forces it to rebuild on next start, picking up the freshly generated certs that are baked in during the image build.

**4. Delete the old certificates and the old CA trust entries**

In a **WSL2 terminal** (or host terminal on macOS/Linux):

```bash
# Delete old cert files so setup regenerates them
rm -f ~/vnla/vanilla/docker/images/nginx/certs/*.crt \
      ~/vnla/vanilla/docker/images/nginx/certs/*.key \
      ~/vnla/vanilla/docker/images/nginx/certs/*.srl

# Remove the old CA from the Linux/WSL2 trust store
# (setup-host.sh will re-add the new one automatically on next run)
sudo rm -f /usr/local/share/ca-certificates/vanilla-dev-ca.crt
```

On **Windows**, also remove the old CA from the Windows certificate store. Run the following in an **elevated PowerShell** (Run as Administrator):

```powershell
certutil -delstore Root "Dev Certificate Authority"
```

**5. Reopen the devcontainer**

Command palette → **"Dev Containers: Reopen in Container"**.

The `initializeCommand` (`setup-host.sh`) will run automatically and:
- Regenerate fresh SSL certificates
- Add the new CA to the Linux and Windows trust stores
- Rebuild and start the infrastructure containers (including nginx) with the new certs

**6. Reopen your browser**

Open a fresh browser window and navigate to your site. The padlock should now be green.

---

#### Other certificate warnings

If your browser shows a generic certificate warning (not `ERR_CERT_AUTHORITY_INVALID`):

1. Check if the CA file exists:
   ```bash
   ls docker/images/nginx/certs/ca.crt
   ```

2. On **macOS**, verify the CA is in your keychain:
   ```bash
   security find-certificate -c "Dev Certificate Authority"
   ```
   If not found, add it manually:
   ```bash
   sudo security add-trusted-cert -d -r trustRoot -p ssl \
       -k /Library/Keychains/System.keychain docker/images/nginx/certs/ca.crt
   ```

3. On **Linux / WSL2 (Linux side)**, verify the CA is installed:
   ```bash
   ls /usr/local/share/ca-certificates/vanilla-dev-ca.crt
   ```
   If not found:
   ```bash
   sudo cp docker/images/nginx/certs/ca.crt /usr/local/share/ca-certificates/vanilla-dev-ca.crt
   sudo update-ca-certificates
   ```

4. On **Windows**, check the cert store:
   ```powershell
   certutil -store Root "Dev Certificate Authority"
   ```
   If not found, add it manually from an elevated PowerShell prompt:
   ```powershell
   certutil -addstore -f ROOT docker\images\nginx\certs\ca.crt
   ```

### Container won't start

- Make sure Docker Desktop is running
- Check that ports 80, 443, and 3306 are not in use by another process:
  ```bash
  # macOS / Linux / WSL2
  lsof -i :80
  lsof -i :443
  ```
  ```powershell
  # Windows PowerShell
  netstat -ano | findstr ":80 "
  netstat -ano | findstr ":443 "
  ```
- If you were previously using `./cli/bin/vnla docker up`, stop those containers first:
  ```bash
  ./cli/bin/vnla docker down
  ```

### "vanilla-network" errors

If you see errors about the network not existing, create it manually:

```bash
docker network create -d bridge vanilla-network
```

### EPERM / EXDEV errors (yarn install fails)

This means the repo is cloned on the Windows NTFS filesystem instead of the WSL2 filesystem. Move the repo to the WSL2 filesystem:

```bash
# Inside WSL2
mv /mnt/c/Repos/vanilla-workspace ~/vnla  # adjust source path as needed
```

Then reopen the project from WSL2.

### EACCES errors during `yarn install` in the devcontainer

If you see `EACCES: permission denied, mkdir '.../node_modules/...'` during `postCreateCommand`, the named volume for `node_modules` may be stale and owned by the wrong user.

To fix it:

1. Stop the devcontainer — command palette → **"Dev Containers: Reopen Folder Locally"** (or just close the editor window).

2. Open a plain WSL2 terminal (Ubuntu or your chosen distro) — **not** a terminal inside the devcontainer — and remove the stale volumes:

   ```bash
   docker volume rm vanilla_devcontainer-node-modules vanilla_devcontainer-yarn-cache
   ```

3. Reopen in the devcontainer — command palette → **"Dev Containers: Rebuild and Reopen in Container"**.

### Slow performance on Windows

Make sure your project is on the WSL2 filesystem (`~/vnla/vanilla`), **not** on the Windows filesystem (`/mnt/c/...`). Cross-filesystem Docker mounts are significantly slower.

### Hosts not resolving

If `https://vanilla.local/{YOUR-SITENAME}` doesn't resolve, check your hosts file:

- **macOS / Linux / WSL2:** `grep vanilla.local /etc/hosts`
- **Windows:** `findstr vanilla.local C:\Windows\System32\drivers\etc\hosts`

Each hostname should have entries for both `127.0.0.1` and `::1`.

## Relationship to `vnla docker`

This dev container setup is **independent** from the existing `./cli/bin/vnla docker up` workflow. They can coexist in the same repository but should not run simultaneously (they use the same ports).

| | `./cli/bin/vnla docker up` | Dev Container |
|---|---|---|
| Requires PHP on host | Yes | No |
| Editor integration | None | Cursor, VS Code, JetBrains |
| Cross-platform | macOS + Linux | macOS + Linux + Windows |
| How to start | `./cli/bin/vnla docker up` | "Reopen in Container" |
| Workspace location | Host filesystem | Inside container |

If you're already using `./cli/bin/vnla docker up` and it works for you, there's no need to switch. The dev container is an alternative that removes the need for host-side PHP/Node/Composer installations.
