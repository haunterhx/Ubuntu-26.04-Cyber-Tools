# Cyber Bootstrapper

Cyber Bootstrapper is a Bash script that provisions a Debian/Ubuntu workstation for cyber defense work. It installs tooling in modular groups (base, hardening, CTI, network analysis, DFIR), logs every action, and reports any package that failed to install.

## Requirements

- Debian or Ubuntu based system (uses `apt-get` and `dpkg`)
- A non-root user with `sudo` privileges
- Internet access to the distribution mirrors and PyPI

## Usage

```bash
chmod +x cyber-bootstrapper.sh
./cyber-bootstrapper.sh <module> [module ...]
```

Running the script with no arguments prints the help menu and exits.

### Examples

```bash
# Install everything
./cyber-bootstrapper.sh all

# Install only network and DFIR tooling (base is added automatically)
./cyber-bootstrapper.sh network dfir

# Harden the OS and install CTI tooling
./cyber-bootstrapper.sh harden cti
```

## Modules

| Module    | Purpose |
|-----------|---------|
| `base`    | Core utilities and language runtimes. Always runs, even if not specified. |
| `harden`  | Full system upgrade, host firewall, auditing, and kernel/network hardening. |
| `cti`     | Threat intelligence and OSINT clients and libraries. |
| `network` | Packet capture, scanning, and network security monitoring. |
| `dfir`    | Disk, file, and memory forensics. |
| `all`     | Runs `harden base cti network dfir` in that order. Must be the first argument. |

### base

- **apt:** `build-essential git curl wget jq yq ripgrep fd-find bat fzf tmux vim neovim htop btop tree unzip p7zip-full zstd python3 python3-pip python3-venv python3-dev pipx golang-go openssl gnupg ca-certificates sqlite3 xxd hexyl file`
- Runs `pipx ensurepath` and adds `~/.local/bin` to `PATH` for the current session
- Creates `~/tools`

### harden

- Runs `apt-get update` and `apt-get full-upgrade`
- **apt:** `ufw unattended-upgrades apparmor apparmor-utils auditd lynis needrestart debsums`
- UFW: deny incoming, allow outgoing, enabled
- Enables and starts `auditd`
- Configures unattended upgrades non-interactively
- Writes `/etc/sysctl.d/99-cyber-hardening.conf` and reloads with `sysctl --system`:

| Setting | Value | Effect |
|---------|-------|--------|
| `kernel.kptr_restrict` | 2 | Hides kernel pointers from all users |
| `kernel.dmesg_restrict` | 1 | Restricts `dmesg` to privileged users |
| `kernel.yama.ptrace_scope` | 1 | Limits ptrace to descendant processes |
| `kernel.unprivileged_bpf_disabled` | 1 | Blocks unprivileged eBPF |
| `net.core.bpf_jit_harden` | 2 | Hardens the BPF JIT for all users |
| `net.ipv4.conf.all.rp_filter` | 1 | Strict reverse-path filtering |
| `net.ipv4/ipv6.conf.all.accept_redirects` | 0 | Ignores ICMP redirects |
| `net.ipv4.conf.all.send_redirects` | 0 | Does not send ICMP redirects |
| `net.ipv4.tcp_syncookies` | 1 | SYN flood protection |

After completion, run `sudo lynis audit system` to obtain a baseline hardening score.

### cti

- **pipx:** `shodan censys stix2-validator`
- Creates a virtual environment at `~/tools/venv-cti` containing `pymisp stix2 taxii2-client OTXv2 vt-py`

Activate the environment with:

```bash
source ~/tools/venv-cti/bin/activate
```

API keys (`VT_API_KEY`, `SHODAN_API_KEY`, `OTX_API_KEY`) should be stored as environment variables in a file under `~/.config`, not typed into the shell where they persist in history.

### network

- Preseeds Wireshark to allow non-root capture and adds the current user to the `wireshark` group
- **apt:** `wireshark tshark tcpdump nmap ncat netcat-openbsd whois dnsutils mtr-tiny iperf3 socat ngrep tcpflow suricata suricata-update arp-scan masscan`
- **pipx:** `mitmproxy`

Pull the ET Open ruleset for Suricata with `sudo suricata-update`.

### dfir

- **apt:** `sleuthkit testdisk foremost scalpel ewf-tools libimage-exiftool-perl binwalk dc3dd guymager plaso sqlitebrowser`
- **pipx:** `volatility3 sigma-cli`

## How It Works

1. **Setup:** Creates `~/.cyber-bootstrapper/` for the log file if it does not exist.
2. **Privilege check:** Exits if run as root. Packages are installed via `sudo`, while pipx tools and the CTI venv are installed in the user's home directory.
3. **Argument handling:** Prints help if no modules are given. Expands `all` to the full module list and prepends `base` if it is missing.
4. **Authentication:** Calls `sudo -v` once up front to cache credentials.
5. **Execution:** Each module name is checked against defined functions with `declare -F`. Unknown names are logged as warnings and skipped.
6. **Idempotent installs:** `apt_install` skips packages already reported by `dpkg -s`; each package is installed individually so one failure does not abort the run.
7. **Failure tracking:** Failed apt packages, pipx packages, and the CTI venv are collected in a `FAILED` array and printed as a summary at the end.
8. **Completion:** Prompts the user to log out and back in so group membership (`wireshark`) and `PATH` changes take effect.

The script uses `set -uo pipefail` without `-e`, so individual failures are recorded rather than terminating the run.

## Logging

All output from helper functions and package managers is appended to:

```
~/.cyber-bootstrapper/cyberbootstrapper.log
```

Lines prefixed `[+]` are informational; lines prefixed `[!]` are warnings or failures.

## Post-Install Checklist

- Log out and back in
- `sudo suricata-update`
- `sudo lynis audit system`
- Configure CTI API keys under `~/.config`
