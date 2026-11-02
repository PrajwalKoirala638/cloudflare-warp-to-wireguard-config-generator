# ☁️🔒 cloudflare-warp-to-wireguard-config-generator

![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)
![WireGuard](https://img.shields.io/badge/WireGuard-88171A?style=for-the-badge&logo=wireguard&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare_WARP-F38020?style=for-the-badge&logo=cloudflare&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

Generate a free, native **WireGuard configuration** for [Cloudflare WARP](https://developers.cloudflare.com/warp-client/) in seconds — allowing you to connect using the **standard, open-source WireGuard client** instead of Cloudflare's proprietary application, and securely route all your traffic through Cloudflare's global edge network (330+ cities across 120+ countries).

🚫 **No account. No email. No credit card. No subscription. No bandwidth limits.**  
Cloudflare's consumer WARP tier is 100% free. That makes this setup an ideal, zero-cost solution for encrypting your traffic on untrusted networks like hotel Wi-Fi 🏨, airports ✈️, coffee shops ☕, or restrictive ISPs 🌐.

---

## 📑 Table of Contents

- [🤔 Why Native WireGuard vs. the Official WARP App?](#-why-native-wireguard-vs-the-official-warp-app)
- [⚙️ Under the Hood: How It Works](#️-under-the-hood-how-it-works)
- [📄 Anatomy of the Generated Config](#-anatomy-of-the-generated-config)
- [📋 Requirements](#-requirements)
- [🚀 Quick Start & Usage](#-quick-start--usage)
- [📲 Importing into WireGuard](#-importing-into-wireguard)
- [✅ Verifying Your Connection](#-verifying-your-connection)
- [🔧 Advanced Customization & Tweaks](#-advanced-customization--tweaks)
- [🛠️ Troubleshooting](#️-troubleshooting)
- [⚠️ Privacy & Security Notes](#️-privacy--security-notes)
- [📜 License](#-license)

---

## 🤔 Why Native WireGuard vs. the Official WARP App?

Under the hood, Cloudflare WARP is built on the WireGuard protocol (specifically Cloudflare's Rust implementation, `BoringTun`). Their official desktop and mobile apps are essentially WireGuard clients wrapped in a proprietary UI and background daemon.

This script skips the wrapper: it executes the exact same one-time registration API call the official app makes behind the scenes, then extracts your credentials into a standard `.conf` file for the [official WireGuard client](https://www.wireguard.com/install/).

### 📊 Feature Comparison

| Feature / Aspect          | 🐉 Native WireGuard (`.conf`)                                 | ☁️ Official Cloudflare WARP App                   |
| :------------------------ | :------------------------------------------------------------ | :------------------------------------------------ |
| **Client Software**       | Official open-source WireGuard app                            | Proprietary Cloudflare client + background daemon |
| **System Resource Usage** | 🪶 Ultra-lightweight (Kernel-space on Linux)                  | 🐘 Heavy background service (`warp-svc`)          |
| **Telemetry & Analytics** | 🔒 Zero client telemetry                                      | 📊 Sends client diagnostic/crash data             |
| **Router / NAS Support**  | ✅ Yes (OpenWrt, pfSense, OPNsense, GL.iNet, Synology)        | ❌ No (Desktop & Mobile OS only)                  |
| **Config Customization**  | 🎛️ Full control (Custom DNS, MTU, Split-Tunneling, Endpoints) | 🔒 Locked down / Hidden behind GUI                |
| **Multi-VPN Management**  | 🧰 Manage alongside all your other WireGuard tunnels          | 🧩 Requires a separate dedicated app              |
| **Cost & Bandwidth**      | 💸 100% Free & Unlimited                                      | 💸 100% Free & Unlimited (Base tier)              |
| **WARP+ (Argo Routing)**  | ❌ Standard WARP routing only                                 | ✅ Supported (Paid subscription)                  |

---

## ⚙️ Under the Hood: How It Works

This repository contains a single standalone Bash script, `warp-setup.sh`, that runs through 5 automated steps:

1. 📦 **Dependency Check:** Verifies that `curl`, `jq`, `wg` (WireGuard CLI tools), and `qrencode` are installed. If anything is missing, it detects your Linux distribution and installs them via your native package manager.
2. 🔑 **Local Keypair Generation:** Runs `wg genkey` and `wg pubkey` to create a fresh Curve25519 private/public keypair locally in memory — **your private key never leaves your machine**.
3. 🌐 **Cloudflare API Registration:** Sends an HTTP `POST` request containing _only_ your public key and a standard timestamp to `https://api.cloudflareclient.com/v0a2158/reg`. Cloudflare responds with a JSON payload containing your newly provisioned Device ID, internal IPv4/IPv6 tunnel addresses, and peer endpoint details.
4. 📝 **Config Assembly:** Parses the JSON payload with `jq` and injects your local private key and Cloudflare's peer details into a clean, standards-compliant WireGuard `.conf` file.
5. 📱 **Dual Output:** Saves the `.conf` file to your current directory and pipes it through `qrencode -t ansiutf8` to render a scannable QR code directly inside your terminal window.

> 💡 **Zero Footprint:** This script does **not** run a VPN, stay open in the background, modify your network interfaces, or install any background services. It strictly generates your `.conf` file and exits cleanly.

---

## 📄 Anatomy of the Generated Config

Each run creates a timestamped configuration file in your current directory:

```text
cf-warp-261102.conf
```

> 📏 **Why the short filename?** Linux network interfaces (`wg-quick`) use the filename (minus `.conf`) as the interface name, which the Linux kernel strictly limits to **15 characters (`IFNAMSIZ`)**. `cf-warp-YYMMDD` is exactly 14 characters, ensuring zero import errors across Linux, macOS, Windows, iOS, and Android.

### Example Output Breakdown

```ini
[Interface]
# Your locally generated Curve25519 private key (Keep this secret!)
PrivateKey = <YOUR_LOCAL_PRIVATE_KEY>

# Your unique Cloudflare-assigned internal WARP IPs (IPv4 /32 and IPv6 /128)
Address = 172.16.0.2/32, 2606:4700:110:8a3f:xxxx:xxxx:xxxx:xxxx/128

# Cloudflare's ultra-fast 1.1.1.1 DNS resolvers (IPv4 + IPv6)
DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001

# Optimal MTU for WARP encapsulation overhead
MTU = 1280

[Peer]
# Cloudflare WARP's universal public key
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=

# Route ALL IPv4 and IPv6 traffic through the tunnel
AllowedIPs = 0.0.0.0/0, ::/0

# Cloudflare's Anycast WireGuard Endpoint (Automatically routes to your nearest PoP)
Endpoint = engage.cloudflareclient.com:2408
```

---

## 📋 Requirements

| Component                   | Details                                                                                                                                                                     |
| :-------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 🐧 **OS to run the script** | Any Linux environment with `bash` (Ubuntu, Debian, Fedora, RHEL, CentOS, Rocky, Alma, Arch, Manjaro, Alpine) — works great on bare metal, VMs, Docker, or **Windows WSL2**. |
| 🛠️ **Dependencies**         | `curl`, `jq`, `wireguard-tools` (`wg`), `qrencode` _(Auto-installed by the script if missing)_.                                                                             |
| 🛡️ **Privileges**           | Standard user if dependencies are already installed; `sudo` / `root` only if packages need to be installed.                                                                 |
| 📲 **Client Device**        | Any device running the [WireGuard App](https://www.wireguard.com/install/) (iOS, Android, Windows, macOS, Linux, or a compatible Router/NAS).                               |

---

## 🚀 Quick Start & Usage

1. **Make the script executable and run it:**

```bash
chmod +x warp-setup.sh
bash warp-setup.sh
```

2. **If you are missing dependencies** and aren't logged in as `root`, run it with `sudo` so it can install them automatically:

```bash
sudo bash warp-setup.sh
```

### 🖥️ What You'll See in Terminal:

- ✅ Step-by-step progress checks
- 🪪 Your WARP account metadata (Account ID, Device ID, Account Type, WireGuard Public Key)
- 🔳 An instant **ANSI UTF-8 QR code** rendered directly in your terminal
- 📄 The complete raw `.conf` file text

---

## 📲 Importing into WireGuard

### 📱 Mobile (iOS & Android)

1. Install the official **[WireGuard app](https://www.wireguard.com/install/)** from the App Store or Google Play.
2. Open the app, tap the **`+`** button, and select **Create from QR code**.
3. Point your phone's camera at the QR code printed in your terminal.
4. Name the tunnel (e.g., `Cloudflare-WARP`) and flip the toggle to connect.

### 💻 Desktop (Windows, macOS, Linux GUI)

1. Install the official **[WireGuard client](https://www.wireguard.com/install/)**.
2. Click **Import tunnel(s) from file** (or press `Ctrl+O` / `Cmd+O`).
3. Select the generated `cf-warp-YYMMDD.conf` file and click **Activate**.

### 🐧 Linux CLI (`wg-quick`)

To run the tunnel directly from a Linux terminal or headless server:

```bash
# Copy the config to /etc/wireguard/
sudo cp cf-warp-261102.conf /etc/wireguard/

# Bring the tunnel up
sudo wg-quick up cf-warp-261102

# Check tunnel handshake & transfer status
sudo wg show

# Bring the tunnel down when done
sudo wg-quick down cf-warp-261102
```

---

## ✅ Verifying Your Connection

Once your tunnel is active, you can verify that your traffic is encrypted and routing through Cloudflare's WARP network using Cloudflare's built-in trace endpoint:

```bash
curl -s https://www.cloudflare.com/cdn-cgi/trace
```

**Expected Output:**

```ini
ip=104.28.xx.xx
loc=US
colo=SFO
warp=on
```

- **`warp=on`**: Confirms your traffic is actively passing through the Cloudflare WARP WireGuard tunnel! _(If it says `warp=off`, your traffic is not going through the tunnel)._
- **`colo=XXX`**: Shows the 3-letter IATA airport code of the nearest Cloudflare Data Center (PoP) handling your connection.

_(On a phone or browser, simply visit **[https://1.1.1.1/help](https://1.1.1.1/help)** and check that **"Connected to 1.1.1.1"** and **"WARP"** says **Yes**)._

---

## 🔧 Advanced Customization & Tweaks

Because you have the raw `.conf` file, you can customize it before or after importing to suit different networks and use cases:

### 1. 🛡️ Block Malware or Adult Content via DNS (1.1.1.1 for Families)

Replace the `DNS = ...` line in your `.conf` file to get automatic network-level filtering without installing extra software:

- **Block Malware & Phishing:**
  ```ini
  DNS = 1.1.1.2, 1.0.0.2, 2606:4700:4700::1112, 2606:4700:4700::1002
  ```
- **Block Malware + Adult Content:**
  ```ini
  DNS = 1.1.1.3, 1.0.0.3, 2606:4700:4700::1113, 2606:4700:4700::1003
  ```

### 2. 🧱 Bypass Strict Firewalls (Alternative Ports & Endpoints)

If a restrictive hotel, school, or corporate firewall blocks UDP port `2408` or blocks DNS resolution for `engage.cloudflareclient.com`, you can edit the `Endpoint =` line in the `[Peer]` section to use direct Anycast IPs and alternative ports:

- **Direct IPv4 Endpoints:** `162.159.192.1` or `162.159.193.1`
- **Direct IPv6 Endpoints:** `[2606:4700:d0::a29f:c001]` or `[2606:4700:d0::a29f:c101]`
- **Supported UDP Ports:** `2408` (default), `500` (IKEv2 standard port — rarely blocked!), `1701`, or `4500`

_Example firewall-friendly endpoint:_

```ini
Endpoint = 162.159.192.1:500
```

### 3. 💓 Fix Dropped Connections Behind NAT (`PersistentKeepalive`)

If you are using this config on a router or a device that stays connected 24/7 behind a strict NAT firewall, add this line under the `[Peer]` section to keep the UDP state table alive:

```ini
PersistentKeepalive = 25
```

---

## 🛠️ Troubleshooting

| Issue / Symptom                                 | Cause                                                                 | Solution                                                                                                                                                                                       |
| :---------------------------------------------- | :-------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ❌ **`command not found` during run**           | Script lacked permissions to install missing tools.                   | Re-run with `sudo bash warp-setup.sh`, or install `curl jq wireguard-tools qrencode` manually.                                                                                                 |
| 🌐 **Connected, but pages won't load**          | Captive portal or blocked UDP port `2408`.                            | 1. Disconnect VPN, open a browser, and complete the hotel/airport Wi-Fi login page.<br>2. Change endpoint port to `:500` or `:4500` (see [Advanced Tweaks](#-advanced-customization--tweaks)). |
| 🐢 **Slow speeds or packet fragmentation**      | Network path has lower MTU overhead (e.g., PPPoE or mobile hotspots). | Lower `MTU = 1280` in the `[Interface]` section to `MTU = 1240` or `MTU = 1200`.                                                                                                               |
| 🐧 **`resolvconf: command not found` on Linux** | Missing DNS handler for `wg-quick` on Debian/Ubuntu/Arch.             | Install `openresolv` or `systemd-resolved` (e.g., `sudo apt install openresolv`).                                                                                                              |
| ❓ **`Unrecognized distro` error**              | Running on NixOS, openSUSE, Gentoo, or macOS.                         | Manually install `curl`, `jq`, `wireguard-tools`, and `qrencode`, then run `bash warp-setup.sh` as a normal user.                                                                                 |

---

## ⚠️ Privacy & Security Notes

- 🔄 **One Config Per Device (No Concurrent Reuse):** Every time you run `warp-setup.sh`, it generates a brand-new keypair and registers a distinct device slot with Cloudflare. Do **not** run the same `.conf` file on two devices simultaneously (e.g., your laptop and phone at the same time), or their WireGuard handshakes will collide and drop packets. Simply run the script again to generate a second `.conf` for your second device!
- 🕵️ **Security vs. Anonymity:** WARP encrypts 100% of your traffic between your device and Cloudflare's nearest edge server. This completely protects you from local packet sniffing on public Wi-Fi, ISP snooping, and DNS hijacking. However, **WARP is not an anonymity or geo-spoofing tool** — websites will see a Cloudflare egress IP localized to your current region, and Cloudflare processes the traffic according to their [Consumer Privacy Policy](https://www.cloudflare.com/application/privacypolicy/).
- 🔐 **Guard Your `.conf` File:** Your generated `.conf` file contains your unencrypted WireGuard `PrivateKey`. Treat it like a password — set restrictive file permissions (`chmod 600 cf-warp-*.conf`) and **never** commit it to a public Git repository!

---

## 📜 License

Distributed under the **MIT License**. Do whatever you want with this script — modify, share, or integrate it into your own dotfiles. Provided _as-is_ with no warranty.
