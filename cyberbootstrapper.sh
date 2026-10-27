#!/bin/bash
# Version 1.0
# Author: haunterhx
set -uo pipefail

DIRECTORY="$HOME/.cyber-bootstrapper"
LOG="$HOME/.cyber-bootstrapper/cyberbootstrapper.log"
FAILED=()
TOOLS_DIR="$HOME/tools"

# log() displays information message and appends a message to the log file
log() { printf '\n[+] %s\n' "$*" | tee -a "$LOG"; }
# warn() displays warning message and appends to the log file
warn() { printf '[!] %s\n' "$*" | tee -a "$LOG"; }

# Check if the main usage directory exists, if not create it.
if ! [ -d "$DIRECTORY" ]; then
	echo "[+] Creating $DIRECTORY"
	mkdir $DIRECTORY
	log "$DIRECTORY was created"
fi

# Help Menu
show_help() {
	cat << EOF
Usage: $0 [OPTIONS]

Description:
	Cyber Bootstrapper automates the installation of cybersecurity tools.

Options:
	-h, --help		Display this help message and exit

Modules:
	harden base network dfir cti

Example:
	$0
EOF
}

#---- apt_install ----#
# - Installs specified package using apt-get
# - Iterates through all packages passed as args
# - Checks if the package is installed
# - Skips installed packages and installs missing packages with admin privileges
apt_install() {
	for pkg in "$@"; do 
		if dpkg -s "$pkg" &>/dev/null; then continue; fi
		if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >>"$LOG" 2>&1; then
			warn "apt: failed $pkg"; FAILED+=("apt:$pkg")
		fi
	done
}

#---- pipx_install ----#
# - Installs Python packages via the pipx cli installer
# - Iterates through each pacakge and installs in isolated Py environment
pipx_install() {
	for pkg in "$@"; do 
		if ! pipx install "$pkg" >> "$LOG" 2>&1; then
			warn "pipx: failed $pkg"; FAILED+=("pipx:$pkg")
		fi
	done
}

# Base Tool Installation
base() {
	log "Base Tooling"
	sudo apt-get update
	apt_install build-essential git curl wget jq yq ripgrep fd-find bat fzf \
				tmux vim neovim htop btop tree unzip p7zip-full zstd \
				python3 python3-pip python3-venv python3-dev pipx \
				golang-go openssl gnupg ca-certificates \
				sqlite3 xxd hexyl file 
	pipx ensurepath >>"$LOG" 2>&1
	export PATH="$HOME/.local/bin:$PATH"
	echo "[+] Creating Tools Directory..."
	sleep 1
	mkdir -p "$TOOLS_DIR"
}
# Harden the OS
harden() {
	log "Hardening your OS..."
	sudo apt-get update && sudo apt-get -y full-upgrade
	apt_install ufw unattended-upgrades apparmor apparmor-utils auditd \
				lynis needrestart debsums
	sudo ufw default deny incoming
	sudo ufw default allow outgoing 
	sudo ufw --force enable 
	sudo systemctl enable --now auditd 
	sudo dpkg-reconfigure -f noninteractive unattended-upgrades
	# Kernel and Network hardening
	sudo tee /etc/sysctl.d/99-cyber-hardening.conf > /dev/null <<'EOF'
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_syncookies - 1
EOF
	sudo sysctl --system >>"$LOG" 2>&1
	log "Run 'sudo lynis audit system' later for a baseline score"
}
# Cyber Threat Intel Tool Installation
cti() {
	log "CTI / OSINT Tooling"
	pipx_install shodan censys stix2-validator
	python3 -m venv "$TOOLS_DIR/venv-cti"
	"$TOOLS_DIR/venv-cti/bin/pip" install -q --upgrade pip \
		pymisp stix2 taxii2-client OTXv2 vt-py >>"$LOG" 2>&1 \
		|| FAILED+=("venv:cti-libs")
	log "Set API Keys via env vars (VT_API_KEY, SHODAN_API_KEY, OTX_API_KEY) in ~/.config, not in shell history!"
}
# Network Tool Installation
network() {
	log "Network Analysis / NSM Tooling"
	echo "wireshark-common wireshark-common/install-setuid boolean true" \
		| sudo debconf-set-selections
	apt_install wireshark tshark tcpdump nmap ncat netcat-openbsd \
		whois dnsutils mtr-tiny iperf3 socat ngrep tcpflow \
		suricata suricata-update arp-scan masscan 
	sudo usermod -aG wireshark "$USER"
	pipx_install mitmproxy
	log "Suricata: run 'sudo suricata-update' to pull ET Open rules."
}
# DFIR Tooling Installation
dfir() {
	log "DFIR / Forensic Tooling"
	apt_install sleuthkit testdisk foremost scalpel ewf-tools \
				libimage-exiftool-perl binwalk dc3dd guymager \
				plaso sqlitebrowser
	pipx_install volatility3 sigma-cli
}

main() {
	# Ensure we are running non-root
	[[ $EUID -eq 0 ]] && { echo "Run as a normal user, not root!"; exit 1; }

	# Display help when no arguments passed
	[[ $# -eq 0 ]] && { show_help ; exit 0; }

	# Prompt for sudo authentication
	sudo -v

	# Contains all the arguments passed to the script
	local mods=("$@")
	
	# If ALL is passed as an argument
	[[ "${mods[0]}" == "all" ]] && mods=(harden base cti network dfir)

	# Prepend base to the array, ensuring base is always included
	[[ " ${mods[*]} " != *" base "* ]] && mods=(base "${mods[@]}")	


	# Check if modules are available or unknown
	for m in "${mods[@]}"; do 
		declare -F "$m" >/dev/null || { warn "unknown module $m"; continue; }
		$m 
	done

	log "Done. Log: $LOG"

	if ((${#FAILED[@]})); then 
		warn "Failed items (review log):"; printf '		%s\n' "${FAILED[@]}" | tee -a "$LOG"
	fi

	log "Log out and back in."
	
}

main "$@"
