#!/bin/bash
# warp-setup.sh
#
# What this script does, step by step:
#   1. Checks for required programs (curl, jq, wg, qrencode) and installs any that are missing
#   2. Registers a new free device with Cloudflare WARP (or loads your existing registration)
#   3. Builds a ready-to-use WireGuard VPN configuration and prints it to the screen
#
# How to use it:
#   ./warp-setup.sh > warp.conf
#
# How to customize it:
#   To change settings like DNS servers or file names, edit the values inside generate_warp_config below.
#
# License: MIT - You are free to use, modify, and share this script with no warranty.

set -euo pipefail # Safety mode: stop immediately if any command fails (-e), an unset variable is used (-u), or a piped command fails (-o pipefail)

# ==============================================================================
# STEP 1: Check for required programs and install any that are missing
# ==============================================================================

function install_required_tools() { # Define the function that checks for and installs required software
	# This function takes no inputs; it ensures curl, jq, wg, and qrencode are installed on your system

	local missing_tools=()                     # Create an empty list to keep track of any programs that are not installed yet
	for tool in curl jq wg qrencode; do        # Loop through each of the four required programs one by one
		if ! command -v "$tool" &>/dev/null; then # Check if the program is missing from the system (hiding the check's output)
			missing_tools+=("$tool")                 # Add the missing program's name to our list
		fi                                        # End of the check for this single program
	done                                       # Finished checking all four programs

	if [[ ${#missing_tools[@]} -eq 0 ]]; then             # Check if our list of missing programs is completely empty (count is 0)
		echo "All required tools are already installed." >&2 # Print a status message to the screen (using >&2 so it doesn't mix with the final config output)
		return 0                                             # Exit this function early because nothing needs to be installed
	fi                                                    # End of the "already installed" check

	echo "Missing tools: ${missing_tools[*]}" >&2 # Show the user which programs are missing before we try to install them

	if [[ "$EUID" -ne 0 ]]; then                                                        # Check if the user is NOT running as administrator/root (root always has user ID 0)
		echo "Error: installing packages requires root. Re-run this script with sudo:" >&2 # Explain that administrator permissions are needed to install software
		echo "  sudo $0" >&2                                                               # Show the exact command the user needs to copy and run
		exit 1                                                                             # Stop the script with an error code (1) because we cannot install software without root
	fi                                                                                  # End of the administrator permission check

	echo "Running as root - installing missing tools..." >&2 # Let the user know we have permission and are starting the installation

	local distro="unknown"          # Create a variable to hold the Linux operating system name, defaulting to "unknown"
	if [ -f /etc/os-release ]; then # Check if the standard Linux system identification file exists
		. /etc/os-release              # Load the contents of that file so we can read system variables like $ID
		distro="$ID"                   # Save the operating system name (like "ubuntu", "fedora", or "arch") into our variable
	fi                              # End of the operating system detection check

	case "$distro" in                                                                        # Choose the right installation command based on which Linux system is running
	ubuntu | debian | raspbian | pop | kali | linuxmint | neon)                              # If running Ubuntu, Debian, or a related system:
		apt-get update                                                                          # Refresh the list of available software packages from the internet
		apt-get install -y curl jq wireguard-tools qrencode                                     # Install the required tools automatically (-y answers "yes" to prompts)
		;;                                                                                      # Done with the Ubuntu/Debian section
	fedora | centos | rhel | almalinux | rocky | ol)                                         # If running Fedora, Red Hat, CentOS, or a related system:
		yum install -y curl jq wireguard-tools qrencode                                         # Install the required tools automatically without asking for confirmation
		;;                                                                                      # Done with the Fedora/Red Hat section
	arch | archarm | manjaro)                                                                # If running Arch Linux or Manjaro:
		pacman -Sy --noconfirm curl jq wireguard-tools qrencode                                 # Refresh the package list and install the tools without asking for confirmation
		;;                                                                                      # Done with the Arch Linux section
	alpine)                                                                                  # If running Alpine Linux (commonly used in lightweight containers):
		apk add --no-cache curl jq wireguard-tools qrencode                                     # Install the tools directly without saving temporary package files
		;;                                                                                      # Done with the Alpine Linux section
	*)                                                                                       # If the Linux system wasn't recognized above:
		echo "Unrecognized distro '$distro' - please install manually: ${missing_tools[*]}" >&2 # Ask the user to install the missing programs themselves
		;;                                                                                      # Done with the unrecognized system section
	esac                                                                                     # End of the operating system installation menu
}                                                                                         # End of the install_required_tools function

# ==============================================================================
# STEP 2: Register with Cloudflare WARP and build the WireGuard configuration
# ==============================================================================

function generate_warp_config() { # Define the function that talks to Cloudflare and creates the VPN config
	# This function takes no inputs; it saves your registration and prints a ready-to-use WireGuard config

	local state_dir=".config"                 # Name of the hidden folder where we will save your account data and VPN config files
	local state_file="$state_dir/device.json" # Path to the file that stores your secret key and Cloudflare account details for future runs

	mkdir -p "$state_dir"  # Create the .config folder if it does not already exist
	chmod 700 "$state_dir" # Lock down the folder so only your user account can open or read it (protects your secret keys)

	local private_key # Create a variable to hold your device's secret WireGuard private key
	local response    # Create a variable to hold the account and server information returned by Cloudflare

	if [[ -f "$state_file" ]]; then                                                                   # Check if a saved registration file already exists from a previous run
		echo "Found an existing WARP registration - reusing it instead of registering a new device." >&2 # Let the user know we are loading their existing account
		private_key=$(jq -r '.private_key' "$state_file")                                                # Read the saved secret private key from the file
		response=$(jq -r '.response' "$state_file")                                                      # Read the saved Cloudflare account details from the file
	else                                                                                              # If no saved file exists, we need to create a brand-new registration
		echo "No existing WARP registration found - registering a new device..." >&2                     # Let the user know we are registering a new device with Cloudflare

		local public_key                              # Create a variable to hold your device's shareable public key
		private_key=$(wg genkey)                      # Generate a brand-new secret private key using the WireGuard tool
		public_key=$(echo "$private_key" | wg pubkey) # Calculate the matching public key from that private key (Cloudflare needs the public one)

		local tos_date                                     # Create a variable to hold the current date and time
		tos_date=$(date -u +"%Y-%m-%dT%H:%M:%S.000+00:00") # Format the current UTC time in the exact timestamp style Cloudflare requires for accepting their Terms of Service

		local request_body                                                                                                                               # Create a variable to hold the registration message we will send to Cloudflare
		request_body="{\"key\":\"$public_key\",\"install_id\":\"\",\"warp_enabled\":true,\"tos\":\"$tos_date\",\"type\":\"Linux\",\"locale\":\"en_US\"}" # Package our public key, timestamp, and device type into a JSON message

		local http_status            # Create a variable to store the web status code from Cloudflare (e.g., 200 means success)
		local response_body_file     # Create a variable to hold the path to a temporary file
		response_body_file=$(mktemp) # Create a blank temporary file to store Cloudflare's reply

		# Note: Keep the next 5 lines free of trailing inline comments so the "\" line continuations work when running the script!
		http_status=$(curl -sS -X POST "https://api.cloudflareclient.com/v0a737/reg" \
			-H "Content-Type: application/json" \
			-d "$request_body" \
			-o "$response_body_file" \
			-w "%{http_code}") || {                                                                      # Send our registration data to Cloudflare, save their reply to the temp file, and record the HTTP status code
			echo "Error: could not reach Cloudflare's WARP registration endpoint (network problem)." >&2 # If the internet connection failed completely, tell the user
			exit 1                                                                                       # Stop the script with an error code
		}                                                                                             # End of the network connection error handler

		if [[ "$http_status" != "200" ]]; then                                                                                           # Check if Cloudflare returned anything other than "200 OK" (meaning something went wrong)
			echo "Error: Cloudflare's WARP API returned HTTP $http_status." >&2                                                             # Show the user the exact error code Cloudflare returned
			if [[ "$http_status" == "429" ]]; then                                                                                          # Check if the error code is 429 ("Too Many Requests")
				echo "This usually means too many device registrations have come from this network recently - wait a while and try again." >&2 # Explain that Cloudflare is temporarily rate-limiting their internet connection
			fi                                                                                                                              # End of the rate-limit explanation
			cat "$response_body_file" >&2                                                                                                   # Print the raw error message from Cloudflare to help with troubleshooting
			exit 1                                                                                                                          # Stop the script with an error code
		fi                                                                                                                               # End of the HTTP status code check

		response=$(cat "$response_body_file") # Read Cloudflare's successful reply from the temporary file into our variable

		if ! echo "$response" | jq -e . &>/dev/null; then                                  # Verify that Cloudflare's reply is valid, readable JSON data
			echo "Error: Cloudflare's WARP API returned something that isn't valid JSON." >&2 # Warn the user that the reply from Cloudflare was corrupted or unexpected
			echo "$response" >&2                                                              # Print the unreadable reply so the user can see what went wrong
			exit 1                                                                            # Stop the script with an error code
		fi                                                                                 # End of the JSON validation check

		# Save both our secret key and Cloudflare's reply into .config/device.json so we don't have to register again next time
		jq -n --arg pk "$private_key" --argjson resp "$response" '{private_key: $pk, response: $resp}' >"$state_file" # Combine the private key and response into a single JSON file
		chmod 600 "$state_file"                                                                                       # Lock the file so only your user account can read or modify it
	fi                                                                                                             # End of the registration and loading block

	local server_public_key                                                               # Create a variable for the Cloudflare VPN server's public key
	local server_endpoint                                                                 # Create a variable for the Cloudflare VPN server's address and port
	local device_ipv4                                                                     # Create a variable for the internal IPv4 address Cloudflare assigned to you
	local device_ipv6                                                                     # Create a variable for the internal IPv6 address Cloudflare assigned to you
	server_public_key=$(echo "$response" | jq -r '.config.peers[0].public_key')           # Extract the server's public key from Cloudflare's JSON data
	server_endpoint=$(echo "$response" | jq -r '.config.peers[0].endpoint.host // empty') # Extract the server's connection address (or leave blank if missing)
	device_ipv4=$(echo "$response" | jq -r '.config.interface.addresses.v4')              # Extract your assigned IPv4 VPN address
	device_ipv6=$(echo "$response" | jq -r '.config.interface.addresses.v6')              # Extract your assigned IPv6 VPN address

	if [[ -z "$server_public_key" || "$server_public_key" == "null" ]]; then # Make sure we actually got a valid public key for the server
		echo "Error: registration failed. Cloudflare's response was:" >&2       # Tell the user that the server key was missing from the response
		echo "$response" >&2                                                    # Print the full response to help figure out why
		exit 1                                                                  # Stop the script with an error code
	fi                                                                       # End of the server public key check

	if [[ -z "$server_endpoint" ]]; then                                               # Make sure we received a valid server address to connect to
		echo "Error: registration succeeded but the response had no server endpoint." >&2 # Tell the user that the server address was missing
		echo "$response" >&2                                                              # Print the full response for troubleshooting
		exit 1                                                                            # Stop the script with an error code
	fi                                                                                 # End of the server address check

	if [[ -z "$device_ipv4" || "$device_ipv4" == "null" ]]; then                    # Make sure Cloudflare gave our device a valid IPv4 address
		echo "Error: registration succeeded but the response had no IPv4 address." >&2 # Tell the user that the IPv4 address was missing
		echo "$response" >&2                                                           # Print the full response for troubleshooting
		exit 1                                                                         # Stop the script with an error code
	fi                                                                              # End of the IPv4 address check

	echo "" >&2                                                                  # Print an empty line to make the screen output easier to read
	echo "=== Account Info ===" >&2                                              # Print a header for the account details section
	echo "Account ID:   $(echo "$response" | jq -r '.account.id')" >&2           # Display your unique Cloudflare WARP account ID
	echo "Device ID:    $(echo "$response" | jq -r '.id')" >&2                   # Display the unique ID for this specific registered device
	echo "Account Type: $(echo "$response" | jq -r '.account.account_type')" >&2 # Display whether the account is "free" or "unlimited" (WARP+)
	echo "License:      $(echo "$response" | jq -r '.account.license')" >&2      # Display your account's license key (can be used to link devices)
	echo "Created:      $(echo "$response" | jq -r '.created')" >&2              # Display the exact date and time this device was registered
	echo "Expires:      $(echo "$response" | jq -r '.account.ttl')" >&2          # Display when the account data expires
	echo "" >&2                                                                  # Print another empty line for spacing

	echo "Building WireGuard config..." >&2 # Let the user know we are assembling the final configuration file

<<<<<<< HEAD
	local interface_address="$device_ipv4/32"                    # Start building the VPN address setting using your IPv4 address (/32 means a single device address)
	if [[ -n "$device_ipv6" && "$device_ipv6" != "null" ]]; then # Check if Cloudflare also gave us a valid IPv6 address
		interface_address="$interface_address,$device_ipv6/128"     # Add the IPv6 address after a comma (/128 means a single IPv6 device address)
	fi                                                           # End of the IPv6 address check
=======
	local interface_address="$device_ipv4/32"                    # start the Address line with just the IPv4 address
	if [[ -n "$device_ipv6" && "$device_ipv6" != "null" ]]; then # if Cloudflare also gave us an IPv6 address
		interface_address="$interface_address,$device_ipv6/128"    # append it to the Address line
	fi                                                           # end of the IPv6 check
>>>>>>> 3ac6de54e8f00973cd5b9a14a6ff5257a43275d3

	local config # Create a variable to hold the complete text of the WireGuard configuration file
	config=$( # Start capturing the template text below into our config variable
		cat <<EOF
[Interface]
PrivateKey = $private_key
Address = $interface_address
DNS = 1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001
MTU = 1280

[Peer]
PublicKey = $server_public_key
AllowedIPs = 0.0.0.0/0,::/0
Endpoint = $server_endpoint
EOF
	) # End of the WireGuard configuration template (lines inside <<EOF to EOF cannot have bash comments, or they would break the WireGuard file)

	echo "" >&2                                         # Print an empty line for spacing
	echo "=== Scan this with the WireGuard app ===" >&2 # Print a header above the QR code
	echo "$config" | qrencode -t ANSIUTF8 >&2           # Convert the configuration text into a scannable QR code right in the terminal for phones/tablets
	echo "" >&2                                         # Print an empty line after the QR code

	local date_stamp             # Create a variable to hold today's date in a short format
	date_stamp=$(date +"%y%m%d") # Get the date as YYMMDD (for example, 261102 for Nov 2, 2026)

	# WireGuard uses the filename (without .conf) as the connection name, and requires it to be
	# 15 characters or fewer. "cf-warp-YYMMDD" is 14 characters, so it will always import cleanly.
	local config_file="$state_dir/cf-warp-${date_stamp}.conf" # Build the file path, e.g., .config/cf-warp-261102.conf
	echo "$config" >"$config_file"                            # Save the finished WireGuard configuration into that file

	echo "Saved config to $config_file" >&2 # Tell the user where the configuration file was saved on their computer

	echo "$config" # Finally, output the pure configuration to standard output (stdout) so "./warp-setup.sh > warp.conf" works cleanly
}               # End of the generate_warp_config function

# ==============================================================================
# STEP 3: Run the functions defined above
# ==============================================================================

install_required_tools # First, make sure all needed tools (curl, jq, wg, qrencode) are installed
generate_warp_config   # Second, register with Cloudflare WARP and generate the VPN configuration
