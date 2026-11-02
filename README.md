# cloudflare-warp-to-wireguard-config-generator

Generate a free WireGuard config for [Cloudflare WARP](https://developers.cloudflare.com/warp-client/) — then connect using the **standard WireGuard app** instead of Cloudflare's own WARP app, and route all of your device's traffic through Cloudflare's network.

No account, no email, no credit card, no subscription. Cloudflare's free WARP tier costs nothing, so this whole setup is 100% free — which makes it a solid option for encrypting your traffic on hotel wifi, airport wifi, coffee shops, or any other network you don't fully trust while traveling.

---

## Why use the WireGuard app instead of the Cloudflare WARP app?

Cloudflare WARP is actually just a hosted WireGuard endpoint under the hood — their official app is a WireGuard client with a friendlier UI wrapped around it. This script skips the wrapper: it does the same one-time registration step the WARP app does behind the scenes, then hands you a plain WireGuard config so you can connect with the regular [WireGuard app](https://www.wireguard.com/install/) instead.

A few reasons people prefer that:

- **One app for everything.** If you already use WireGuard for a home server, a work VPN, or anything else, you can manage your WARP tunnel from the exact same app instead of installing a second, separate one just for Cloudflare.
- **Full manual control over the config.** You can see and edit the raw `[Interface]`/`[Peer]` config yourself — the endpoint, the DNS servers, the MTU, the allowed IP ranges. The official WARP app hides all of this from you.
- **Portability.** A standard `.conf` file works on routers, NAS boxes, headless Linux servers, and any other device that speaks WireGuard — most of which can't run Cloudflare's own app at all.
- **Lighter weight.** The WireGuard apps are minimal, open-source, and don't phone home with telemetry the way a vendor's own client might.
- **No lock-in.** The generated config is just WireGuard. If you ever want to point the same app at a different WireGuard server instead, you already know how — it's the same workflow.

The trade-off: you lose the WARP app's extra features — WARP+ (their paid, faster tier), Cloudflare's DNS-based content filtering options (WARP for Families), and automatic reconnection handling. If you just want "route my traffic through Cloudflare for free," this script gets you there with less software installed.

---

## What this actually is

This is a single shell script, `warp-setup.sh`, that:

1. **Installs what it needs.** Checks for `curl`, `jq`, `wg` (WireGuard's command-line tool), and `qrencode`, and installs anything missing using your distro's package manager.
2. **Generates a keypair.** Creates a fresh WireGuard private/public key pair locally, on your machine — your private key never leaves your computer.
3. **Registers with Cloudflare.** Sends your public key to Cloudflare's WARP registration endpoint, the same API call the official WARP app makes the first time you open it. This gets you a free device slot, an assigned tunnel IP address, and the address of a nearby WARP server.
4. **Builds the config.** Assembles all of that into a standard WireGuard `[Interface]`/`[Peer]` config file.
5. **Hands it to you two ways.** Saves the config to a file, and also prints it as a QR code right in your terminal so you can scan it straight into your phone.

You end up with an ordinary `.conf` file — this script doesn't run a VPN itself, doesn't stay running in the background, and doesn't install any daemon. It just generates the config and exits. The actual tunnel is created and managed entirely by whichever WireGuard app you import the file into.

---

## Requirements

- A Linux machine to **run the script on** (Ubuntu/Debian, Fedora/RHEL/CentOS, Arch, or Alpine) with `bash`
- Root access (or `sudo`) — only needed if the script has to install missing tools; if `curl`, `jq`, `wg`, and `qrencode` are already installed, it won't touch anything else on your system
- The [WireGuard app](https://www.wireguard.com/install/) on whatever device you actually want to **use** the VPN on — this can be a completely different device than the one you ran the script on (e.g. run the script on a Linux laptop, then scan the QR code with your phone)

---

## Usage

```bash
chmod +x warp-setup.sh
bash warp-setup.sh
```

That's it — no flags, no environment variables to configure. Run it and it does everything on its own.

If it needs to install tools and you're not already root, it'll stop and tell you to re-run with `sudo` instead of guessing:

```bash
sudo bash warp-setup.sh
```

---

## What you get

Each run creates a config file in your current directory named like:

```
cf-warp-260831.conf
```

That's `cf-warp-YYMMDD` — the date you ran the script, in `YYMMDD` format. The short name is intentional: WireGuard uses the filename (minus `.conf`) as the tunnel's interface name, and that name has to be 15 characters or fewer to import without errors. `cf-warp-YYMMDD` comes in at 14.

While it runs, you'll also see:

- Status messages as it works through each step
- A summary of your new WARP account (account ID, device ID, plan type, expiry)
- A scannable QR code of the finished config, printed directly in your terminal
- The full config text itself

---

## Importing into WireGuard

**On your phone (iOS / Android):**

1. Install the official [WireGuard app](https://www.wireguard.com/install/) from your app store.
2. Open the app and tap **+** → **Scan from QR code**.
3. Point your camera at the QR code the script printed in your terminal.
4. Give the tunnel a name if asked, then tap the toggle to connect.

**On a computer (Windows / macOS / Linux) or a router/NAS:**

1. Install the official [WireGuard app](https://www.wireguard.com/install/) (or, on a router/NAS, whatever WireGuard support it has built in).
2. Import the `cf-warp-YYMMDD.conf` file the script saved — most WireGuard apps have an "Import tunnel(s) from file" option.
3. Activate the tunnel.

Once it's connected, **all** of your traffic — IPv4 and IPv6 — routes through Cloudflare's WARP network before it reaches the open internet.

---

## Is this really free?

Yes. Cloudflare's free WARP tier doesn't require a paid WARP+ subscription for what this script uses — you're registering as an ordinary free device, exactly like the official WARP app does the first time you open it. There's no cost to generate or use this config, and no usage limits beyond what Cloudflare applies to free WARP accounts in general.

---

## Troubleshooting

- **"command not found" errors when running the script.** Something in the install step didn't work — try running with `sudo` so it can install the missing tool, or install `curl`, `jq`, `wireguard-tools`, and `qrencode` manually with your distro's package manager.
- **Tunnel imports but nothing connects.** Some networks (especially hotel or airport captive-portal wifi) block outbound WireGuard traffic. Try a different network, or check whether the network requires you to log in through a browser first before any VPN traffic will pass.
- **"Unrecognized distro" message.** The script only auto-installs packages on Ubuntu/Debian, Fedora/RHEL-family, Arch, and Alpine. On anything else, install `curl`, `jq`, `wireguard-tools`, and `qrencode` yourself, then run the script again.

---

## A couple of honest notes

- **Each run registers a new device.** Every time you run the script, it creates a brand-new WARP registration and a new config file. Old configs keep working, but running it repeatedly will leave you with several registered devices over time on Cloudflare's side.
- **This isn't anonymity.** It hides your traffic from your immediate network (hotel wifi, an untrusted café, your ISP), which is genuinely useful — but Cloudflare itself can still see your traffic passing through its network, the same as with any VPN provider. Think of it as "don't trust this wifi" protection, not an anonymity tool.
- **Guard the config file.** It contains your WireGuard private key, which is effectively the password to your tunnel. Treat it like a credential — don't share it or commit it to a public repo.

---

## License

MIT — do whatever you want with this, no warranty.
