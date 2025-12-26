#!/bin/bash
# install-snmp.sh – Ansible-ready SNMP (v2c/v3) multi-IP installer
set -e
LOG="/var/log/snmp-test.log"

# ---------- 1. OS detect ----------
if [[ -f /etc/redhat-release ]]; then OS=rhel;
elif [[ -f /etc/debian_version ]]; then OS=debian;
elif [[ -f /etc/SuSE-release || -f /etc/SUSE-brand ]]; then OS=suse;
elif [[ -f /etc/arch-release ]]; then OS=arch;
else echo "Unsupported OS"; exit 1; fi

# ---------- 2. install packages ----------
install_pkg(){
    local pkg="$1"
    case "$OS" in
        rhel)      rpm -q "$pkg" &>/dev/null || yum -y install "$pkg" ;;
        debian)    dpkg -l "$pkg" &>/dev/null 2>&1 || apt-get -y install "$pkg" ;;
        suse)      rpm -q "$pkg" &>/dev/null || zypper -n install "$pkg" ;;
        arch)      pacman -Qi "$pkg" &>/dev/null || pacman -Sy --noconfirm "$pkg" ;;
    esac
}
case "$OS" in
    debian) install_pkg snmpd; install_pkg snmp ;;
    *)      install_pkg net-snmp; install_pkg net-snmp-utils ;;
esac

# ---------- 3. read vars (ENV first, fallback to interactive) ----------
VER=${SNMP_VERSION:-}          # 2c or 3
COMM=${SNMP_COMMUNITY:-public}
USER=${SNMPv3_USER:-}
AUTH_PROT=${SNMPv3_AUTH_PROT:-SHA}
AUTH_PASS=${SNMPv3_AUTH_PASS:-}
PRIV_PROT=${SNMPv3_PRIV_PROT:-AES}
PRIV_PASS=${SNMPv3_PRIV_PASS:-}
# whitelist – space or comma separated
WHITELIST_RAW=${SNMP_WHITELIST:-127.0.0.1}

# interactive only when any key var missing
if [[ -z "$VER" ]]; then
    echo "SNMP version (2c or 3): "; read VER
fi
if [[ "$VER" == "2c" ]]; then
    : "${COMM:=public}"
else
    [[ -z "$USER" ]] && { echo "SNMPv3 user (-u): "; read USER; }
    [[ -z "$AUTH_PASS" ]] && { echo "Auth passphrase (-A): "; read -s AUTH_PASS; echo; }
    [[ -z "$PRIV_PASS" ]] && { echo "Privacy passphrase (-X): "; read -s PRIV_PASS; echo; }
fi
[[ -z "$WHITELIST_RAW" ]] && { echo "Whitelist IPs/networks (space/comma): "; read WHITELIST_RAW; }

# normalize whitelist to array
WHITELIST=${WHITELIST_RAW//,/ }
IFS=' ' read -r -a WHITELIST_ARR <<< "$WHITELIST"
[[ ${#WHITELIST_ARR[@]} -eq 0 ]] && WHITELIST_ARR=("127.0.0.1")

# ---------- 4. build config ----------
CFG="/etc/snmp/snmpd.conf"
cp -f "$CFG" "${CFG}.bak.$(date +%s)" 2>/dev/null || true

cat > "$CFG" <<'TEMPLATE'
###########################################################################
# snmpd.conf  –  Net-SNMP agent configuration
# See snmpd.conf(5) man page for details
###########################################################################

# SECTION: System Information Setup
sysLocation    South Jakarta
sysContact     Support-DTC <support_dtc@datacomm.co.id>
sysServices    72

# SECTION: Agent Operating Mode
master  agentx

# Views  (system + hrSystem groups only)
view   systemonly  included   .1.3.6.1.2.1.1
view   systemonly  included   .1.3.6.1.2.1.25.1

includeDir /etc/snmp/snmpd.conf.d
###########################################################################
# DYNAMIC PART – DO NOT EDIT MANUALLY BELOW
###########################################################################

TEMPLATE

if [[ "$VER" == "2c" ]]; then
    sed -i '/^# createUser/d; /^# rouser/d' "$CFG"
    for ip in "${WHITELIST_ARR[@]}"; do
        echo "rocommunity $COMM $ip -V systemonly" >> "$CFG"
    done
    echo "rocommunity6 $COMM ::1/128 -V systemonly" >> "$CFG"
else
    sed -i '/^rocommunity/d; /^rocommunity6/d' "$CFG"
    echo "createUser $USER $AUTH_PROT \"$AUTH_PASS\" $PRIV_PROT \"$PRIV_PASS\"" >> "$CFG"
    for ip in "${WHITELIST_ARR[@]}"; do
        echo "rouser $USER authpriv -V systemonly $ip" >> "$CFG"
    done
fi

# ---------- 5. service ----------
systemctl enable snmpd
systemctl restart snmpd

# ---------- 6. test & log ----------
TEST_IP=${WHITELIST_ARR[0]}
{
    echo "==== $(date)  SNMPWALK TEST ===="
    if [[ "$VER" == "2c" ]]; then
        snmpwalk -v2c -c "$COMM" localhost 1.3.6.1.2.1.1.1.0
    else
        snmpwalk -v3 -u "$USER" -l authPriv -a "$AUTH_PROT" -A "$AUTH_PASS" \
                 -x "$PRIV_PROT" -X "$PRIV_PASS" localhost 1.3.6.1.2.1.1.1.0
    fi
} >> "$LOG" 2>&1

# ---------- 7. ansible exit codes ----------
[[ $? -eq 0 ]] && { echo "snmpwalk OK"; exit 0; } || { echo "snmpwalk FAILED"; exit 1; }
