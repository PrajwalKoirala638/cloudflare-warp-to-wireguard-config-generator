#!/bin/bash
# warp-setup.sh
#
# What this does, in order:
#   1. Installs the command-line tools this script needs (curl, jq, wg, ...)
#   2. Registers a new device with Cloudflare WARP
#   3. Prints a ready-to-use WireGuard config to stdout
#
# Usage:
#   ./warp-setup.sh > warp.conf
#
# To change behavior (DNS, QR code, account info, etc.), edit the
# hardcoded values inside generate_warp_config below.
#
# License: MIT - do whatever you want with this, no warranty.

set -euo pipefail # stop on any error, stop on unset variables, fail if any part of a pipe fails

# ==============================================================================
# STEP 1: Install required tools (only if something is actually missing)
# ==============================================================================

function install_required_tools() {
	# this function takes no arguments; it makes sure curl, jq, wg, and qrencode are on the PATH

	local missing_tools=()                     # will collect the names of any tools we don't already have
	for tool in curl jq wg qrencode; do        # check each required command one by one
		if ! command -v "$tool" &>/dev/null; then # command -v finds nothing if the tool isn't installed
			missing_tools+=("$tool")                 # remember that this one is missing
		fi                                        # end of the "is it missing" check
	done                                       # end of the loop over required tools

	if [[ ${#missing_tools[@]} -eq 0 ]]; then             # if nothing was added to the array, everything is already installed
		echo "All required tools are already installed." >&2 # let the user know, then...
		return 0                                             # ...skip installation entirely and return early
	fi                                                    # end of the "already installed" check

	echo "Missing tools: ${missing_tools[*]}" >&2 # tell the user what's missing before we try to fix it

	if [[ "$EUID" -ne 0 ]]; then                                                        # EUID is 0 only when running as root (directly or via sudo)
		echo "Error: installing packages requires root. Re-run this script with sudo:" >&2 # explain what's needed
		echo "  sudo $0" >&2                                                               # show the exact command to run
		exit 1                                                                             # stop here instead of guessing at sudo
	fi                                                                                  # end of the root check

	echo "Running as root - installing missing tools..." >&2 # we're root, so the install commands below can run directly

	local distro="unknown"          # will hold the distro ID, e.g. "ubuntu"; "unknown" until we detect it
	if [ -f /etc/os-release ]; then # /etc/os-release exists on basically every modern Linux system
		. /etc/os-release              # load it, which sets $ID, $VERSION_ID, etc. as shell variables
		distro="$ID"                   # save the distro ID (e.g. "ubuntu", "fedora") into our local variable
	fi                              # end of the /etc/os-release check

	case "$distro" in                                                                        # branch based on which distro we detected
	ubuntu | debian | raspbian | pop | kali | linuxmint | neon)                              # Debian-family distros
		apt-get update                                                                          # refresh apt's package index (already root, no sudo needed)
		apt-get install -y curl jq wireguard-tools qrencode                                     # install the tools we need, -y = don't prompt
		;;                                                                                      # end of this case branch
	fedora | centos | rhel | almalinux | rocky | ol)                                         # Red Hat-family distros
		yum install -y curl jq wireguard-tools qrencode                                         # yum installs and upgrades in one step, -y = don't prompt
		;;                                                                                      # end of this case branch
	arch | archarm | manjaro)                                                                # Arch-family distros
		pacman -Sy --noconfirm curl jq wireguard-tools qrencode                                 # sync package index and install, --noconfirm = don't prompt
		;;                                                                                      # end of this case branch
	alpine)                                                                                  # Alpine Linux
		apk add --no-cache curl jq wireguard-tools qrencode                                     # install without keeping a local package cache
		;;                                                                                      # end of this case branch
	*)                                                                                       # anything we didn't recognize
		echo "Unrecognized distro '$distro' - please install manually: ${missing_tools[*]}" >&2 # warn the user
		;;                                                                                      # end of this case branch
	esac                                                                                     # end of the case statement
}                                                                                         # end of install_required_tools

# ==============================================================================
# STEP 2: Register with Cloudflare WARP and print a WireGuard config
# ==============================================================================

function generate_warp_config() {
	# this function takes no arguments; it prints a finished WireGuard config to stdout

	local state_dir=".config"                 # one folder for everything this script saves: the registration and every generated config
	local state_file="$state_dir/device.json" # this file holds our private key + Cloudflare's response, so we don't have to re-register every time

	mkdir -p "$state_dir"  # make sure the state directory exists
	chmod 700 "$state_dir" # keep the directory private, since it will contain a private key

	local private_key # will hold this device's WireGuard private key
	local response    # will hold Cloudflare's registration response (either fresh or cached)

	if [[ -f "$state_file" ]]; then                                                                   # if we've registered before, reuse that registration
		echo "Found an existing WARP registration - reusing it instead of registering a new device." >&2 # explain why we're skipping registration
		private_key=$(jq -r '.private_key' "$state_file")                                                # load the private key we saved last time
		response=$(jq -r '.response' "$state_file")                                                      # load the Cloudflare response we saved last time
	else                                                                                              # no saved registration yet, so register a new one
		echo "No existing WARP registration found - registering a new device..." >&2                     # explain what's about to happen

		local public_key                              # will hold this device's WireGuard public key
		private_key=$(wg genkey)                      # ask the wg tool to generate a fresh private key
		public_key=$(echo "$private_key" | wg pubkey) # derive the matching public key from it

		local tos_date                                     # will hold the "terms of service accepted at" timestamp
		tos_date=$(date -u +"%Y-%m-%dT%H:%M:%S.000+00:00") # current UTC time in the format Cloudflare expects

		local request_body                                                                                                                               # will hold the JSON we send to Cloudflare to register this device
		request_body="{\"key\":\"$public_key\",\"install_id\":\"\",\"warp_enabled\":true,\"tos\":\"$tos_date\",\"type\":\"Linux\",\"locale\":\"en_US\"}" # build the registration payload

		local http_status            # will hold the HTTP status code curl got back
		local response_body_file     # temp file to hold the response body separately from the status code
		response_body_file=$(mktemp) # create a temp file to write the response body into

		http_status=$(curl -sS -X POST "https://api.cloudflareclient.com/v0a737/reg" \
			-H "Content-Type: application/json" \
			-d "$request_body" \
			-o "$response_body_file" \
			-w "%{http_code}") || {                                                                      # -w prints just the status code to stdout; -o saves the body separately
			echo "Error: could not reach Cloudflare's WARP registration endpoint (network problem)." >&2 # curl itself failed (DNS, connection, etc.)
			rm -f "$response_body_file"                                                                  # clean up the temp file
			exit 1                                                                                       # stop the script with a non-zero exit code
		}

		if [[ "$http_status" != "200" ]]; then                                                                                           # anything other than 200 means Cloudflare rejected the request
			echo "Error: Cloudflare's WARP API returned HTTP $http_status." >&2                                                             # tell the user what status code came back
			if [[ "$http_status" == "429" ]]; then                                                                                          # 429 specifically means "too many requests"
				echo "This usually means too many device registrations have come from this network recently - wait a while and try again." >&2 # explain the likely cause
			fi                                                                                                                              # end of the 429-specific hint
			cat "$response_body_file" >&2                                                                                                   # show the raw response body to help debugging
			rm -f "$response_body_file"                                                                                                     # clean up the temp file
			exit 1                                                                                                                          # stop the script with a non-zero exit code
		fi                                                                                                                               # end of the HTTP status check

		response=$(cat "$response_body_file") # read the successful response body
		rm -f "$response_body_file"           # clean up the temp file

		if ! echo "$response" | jq -e . &>/dev/null; then                                  # make sure what we got back is actually valid JSON
			echo "Error: Cloudflare's WARP API returned something that isn't valid JSON." >&2 # explain what went wrong
			echo "$response" >&2                                                              # show the raw response to help debugging
			exit 1                                                                            # stop the script with a non-zero exit code
		fi                                                                                 # end of the JSON validity check

		# Save this registration so future runs reuse it instead of registering a new device every time.
		jq -n --arg pk "$private_key" --argjson resp "$response" '{private_key: $pk, response: $resp}' >"$state_file" # write both pieces to the state file as one JSON object
		chmod 600 "$state_file"                                                                                       # keep the state file private, since it contains a private key
	fi                                                                                                             # end of the "did we already have a registration" check

	local server_public_key                                                               # will hold the Cloudflare WARP server's public key
	local server_endpoint                                                                 # will hold the address:port of the WARP server to connect to
	local device_ipv4                                                                     # will hold the IPv4 address Cloudflare assigned to this device
	local device_ipv6                                                                     # will hold the IPv6 address Cloudflare assigned to this device, if any
	server_public_key=$(echo "$response" | jq -r '.config.peers[0].public_key')           # pull the server's public key out of the JSON
	server_endpoint=$(echo "$response" | jq -r '.config.peers[0].endpoint.host // empty') # pull the server endpoint out of the JSON
	device_ipv4=$(echo "$response" | jq -r '.config.interface.addresses.v4')              # pull our assigned IPv4 address out of the JSON
	device_ipv6=$(echo "$response" | jq -r '.config.interface.addresses.v6')              # pull our assigned IPv6 address out of the JSON, if any

	if [[ -z "$server_public_key" || "$server_public_key" == "null" ]]; then # if the key is empty or literally "null", registration failed
		echo "Error: registration failed. Cloudflare's response was:" >&2       # explain what went wrong
		echo "$response" >&2                                                    # show the raw response to help debugging
		exit 1                                                                  # stop the script with a non-zero exit code
	fi                                                                       # end of the failure check

	if [[ -z "$server_endpoint" ]]; then                                               # the endpoint is required to connect at all
		echo "Error: registration succeeded but the response had no server endpoint." >&2 # explain what went wrong
		echo "$response" >&2                                                              # show the raw response to help debugging
		exit 1                                                                            # stop the script with a non-zero exit code
	fi                                                                                 # end of the endpoint check

	if [[ -z "$device_ipv4" || "$device_ipv4" == "null" ]]; then                    # every device gets an IPv4 address, so this must be present
		echo "Error: registration succeeded but the response had no IPv4 address." >&2 # explain what went wrong
		echo "$response" >&2                                                           # show the raw response to help debugging
		exit 1                                                                         # stop the script with a non-zero exit code
	fi                                                                              # end of the IPv4 check

	echo "" >&2                                                                  # blank line for readability
	echo "=== Account Info ===" >&2                                              # section header
	echo "Account ID:   $(echo "$response" | jq -r '.account.id')" >&2           # print the WARP account ID
	echo "Device ID:    $(echo "$response" | jq -r '.id')" >&2                   # print this device's ID
	echo "Account Type: $(echo "$response" | jq -r '.account.account_type')" >&2 # print free/WARP+ status
	echo "License:      $(echo "$response" | jq -r '.account.license')" >&2      # print the account's license key
	echo "Created:      $(echo "$response" | jq -r '.created')" >&2              # print when this device was registered
	echo "Expires:      $(echo "$response" | jq -r '.account.ttl')" >&2          # print the account expiry
	echo "" >&2                                                                  # blank line for readability

	echo "Building WireGuard config..." >&2 # status message to the user

	local interface_address="$device_ipv4/32"                    # start the Address line with just the IPv4 address
	if [[ -n "$device_ipv6" && "$device_ipv6" != "null" ]]; then # if Cloudflare also gave us an IPv6 address
		interface_address="$interface_address, $device_ipv6/128"    # append it to the Address line
	fi                                                           # end of the IPv6 check

	local config # will hold the finished [Interface]/[Peer] config text
	config=$(
		cat <<EOF
[Interface]
PrivateKey = $private_key
Address = $interface_address
DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001
MTU = 1280

[Peer]
PublicKey = $server_public_key
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $server_endpoint
EOF
	) # end of the here-document that builds $config

	echo "" >&2                                         # blank line for readability
	echo "=== Scan this with the WireGuard app ===" >&2 # section header
	echo "$config" | qrencode -t ANSIUTF8 >&2           # render the config as a terminal QR code
	echo "" >&2                                         # blank line for readability

	local date_stamp             # will hold today's date, used to make the filename unique
	date_stamp=$(date +"%y%m%d") # e.g. 260831 for 2026-08-31 - kept short on purpose, see below

	# WireGuard uses the filename (minus .conf) as the tunnel/interface name, and
	# requires it to be 15 characters or fewer. "cf-warp-YYMMDD" is 14 characters,
	# so this name will always import cleanly into the WireGuard app.
	local config_file="$state_dir/cf-warp-${date_stamp}.conf" # save alongside device.json, in the same state folder
	echo "$config" >"$config_file"                            # write the config to that file

	echo "Saved config to $config_file" >&2 # let the user know where it went

	echo "$config" # also print the finished config to stdout so it can be redirected: ./warp-setup.sh > warp.conf
}               # end of generate_warp_config

# ==============================================================================
# RUN
# ==============================================================================

install_required_tools # step 1: make sure curl, jq, wg, and qrencode are installed
generate_warp_config   # step 2: register with WARP and print the config
