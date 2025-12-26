#!/bin/bash
# install-snmp.sh
# Universal SNMP (v2c / v3) installer & configurator for Linux
# Must be executed as root

set -e
LOG="/var/log/snmp-test.log"

# --------------- 1. Detect OS family ---------------------------------
detect_os(){
    if [[ -f /etc/redhat-release ]]; then
        OS="rhel"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
    elif [[ -f /etc/SuSE-release || -f /etc/SUSE-brand ]]; then
        OS="suse"
    elif [[ -f /etc/arch-release ]]; then
        OS="arch"
    else
        echo "Unsupported OS."; exit 1
    fi
}
detect_os

# --------------- 2. Install packages if missing -----------------------
install_pkg(){
    local pkg="$1"
    if ! rpm -q "$pkg" &>/dev/null || ! dpkg -l "$pkg" &>/dev/null 2>&1; then
        echo "Installing $pkg ..."
        case "$OS" in
            rhel) yum -y install "$pkg" ;;
            debian) apt-get update && apt-get -y install "$pkg" ;;
            suse) zypper -n install "$pkg" ;;
            arch) pacman -Sy --noconfirm "$pkg" ;;
        esac
    else
        echo "$pkg already installed."
    fi
}
install_pkg net-snmp
install_pkg net-snmp-utils      # debian name = snmp snmpd
if [[ "$OS" == "debian" ]]; then
    install_pkg snmp
    install_pkg snmpd
fi

# --------------- 3. Choose version -----------------------------------
echo "=========================================="
echo "  SNMP CONFIGURATION WIZARD"
echo "=========================================="
while true; do
    read -p "SNMP version to configure (2c or 3) : " VER
    [[ "$VER" =~ ^[23]c?$ ]] && break
done

# --------------- 4. Collect parameters --------------------------------
if [[ "$VER" == "2c" ]]; then
    read -p "Community name (default: public) : " COMM
    COMM=${COMM:-public}
    SUMMARY="SNMPv2c community = $COMM
rocommunity $COMM 127.0.0.1"
else
    echo "--- SNMPv3 parameters ---"
    read -p "Security username (-u) : " USER
    read -p "Authentication protocol (-a)  (SHA|MD5) : " AUTH_PROT
    [[ "$AUTH_PROT" != "SHA" && "$AUTH_PROT" != "MD5" ]] && AUTH_PROT="SHA"
    read -s -p "Authentication passphrase (-A) : " AUTH_PASS; echo
    read -p "Privacy protocol (-x)  (AES|DES) : " PRIV_PROT
    [[ "$PRIV_PROT" != "AES" && "$PRIV_PROT" != "DES" ]] && PRIV_PROT="AES"
    read -s -p "Privacy passphrase (-X) : " PRIV_PASS; echo
    read -p "Whitelist IP allowed to query (default: 127.0.0.1) : " WHITE_IP
    WHITE_IP=${WHITE_IP:-127.0.0.1}

    SUMMARY="SNMPv3 user = $USER
auth protocol = $AUTH_PROT
privacy protocol = $PRIV_PROT
whitelist IP  = $WHITE_IP"
fi

# --------------- 5. Show summary & confirm ----------------------------
echo "=========================================="
echo " CONFIGURATION SUMMARY"
echo "=========================================="
echo "$SUMMARY"
echo "=========================================="
read -p "Apply this configuration? (y/N) : " CONF
[[ ! "$CONF" =~ ^[Yy]$ ]] && echo "Cancelled." && exit 0

# --------------- 6. Generate config file ------------------------------
CFG="/etc/snmp/snmpd.conf"
\cp -f $CFG ${CFG}.bak.$(date +%s) 2>/dev/null || true   # backup
: > $CFG          # empty file

if [[ "$VER" == "2c" ]]; then
    cat > $CFG <<EOF
# SNMPv2c
rocommunity $COMM 127.0.0.1
EOF
else
    # v3 user creation
    cat > $CFG <<EOF
# SNMPv3
createUser $USER $AUTH_PROT "$AUTH_PASS" $PRIV_PROT "$PRIV_PASS"
rouser $USER authPriv $WHITE_IP/32
EOF
fi

# --------------- 7. Start / enable service ----------------------------
systemctl enable snmpd
systemctl restart snmpd
echo "SNMP service started."

# --------------- 8. Test with snmpwalk & log --------------------------
echo "Running snmpwalk test ..."
{
  echo "==== $(date)  SNMPWALK TEST ===="
  if [[ "$VER" == "2c" ]]; then
      snmpwalk -v2c -c "$COMM" 127.0.0.1 1.3.6.1.2.1.1.1.0
  else
      snmpwalk -v3 -u "$USER" -l authPriv \
               -a "$AUTH_PROT" -A "$AUTH_PASS" \
               -x "$PRIV_PROT" -X "$PRIV_PASS" \
               "$WHITE_IP" 1.3.6.1.2.1.1.1.0
  fi
} >> "$LOG" 2>&1

if [[ $? -eq 0 ]]; then
    echo "snmpwalk SUCCESS. Full log saved to $LOG"
else
    echo "snmpwalk FAILED. Inspect $LOG"
fi
