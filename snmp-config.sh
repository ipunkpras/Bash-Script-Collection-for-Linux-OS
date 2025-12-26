#!/bin/bash
# install-snmp.sh  –  universal SNMP (v2c / v3) installer & configurator
# Support multiple whitelist IPs / networks
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

# --------------- 2. Install correct packages --------------------------
install_pkg(){
    local pkg="$1"
    case "$OS" in
        rhel)
            rpm -q "$pkg" &>/dev/null || yum -y install "$pkg" ;;
        debian)
            dpkg -l "$pkg" &>/dev/null 2>&1 || apt-get -y install "$pkg" ;;
        suse)
            rpm -q "$pkg" &>/dev/null || zypper -n install "$pkg" ;;
        arch)
            pacman -Qi "$pkg" &>/dev/null || pacman -Sy --noconfirm "$pkg" ;;
    esac
}

case "$OS" in
    debian)
        install_pkg snmpd
        install_pkg snmp
        ;;
    *)
        install_pkg net-snmp
        install_pkg net-snmp-utils
        ;;
esac

# --------------- 3. Choose version -----------------------------------
echo "=========================================="
echo "  SNMP CONFIGURATION WIZARD"
echo "=========================================="
read -p "SNMP version to configure (2c or 3) : " VER
[[ ! "$VER" =~ ^[23]c?$ ]] && { echo "Only 2c or 3 allowed."; exit 1; }

# --------------- 4. Collect parameters --------------------------------
if [[ "$VER" == "2c" ]]; then
    read -p "Community name (default: public) : " COMM
    COMM=${COMM:-public}
else
    echo "--- SNMPv3 parameters ---"
    read -p "Security username (-u) : " USER
    read -p "Auth protocol (-a)  (SHA|MD5) : " AUTH_PROT
    [[ "$AUTH_PROT" != "SHA" && "$AUTH_PROT" != "MD5" ]] && AUTH_PROT="SHA"
    read -s -p "Auth passphrase (-A) : " AUTH_PASS; echo
    read -p "Privacy protocol (-x)  (AES|DES) : " PRIV_PROT
    [[ "$PRIV_PROT" != "AES" && "$PRIV_PROT" != "DES" ]] && PRIV_PROT="AES"
    read -s -p "Privacy passphrase (-X) : " PRIV_PASS; echo
fi

# >>>  MULTIPLE WHITELIST IP  <<<
echo "Enter whitelist IPs/networks (space or comma separated) e.g. 192.168.1.10 10.0.0.0/24"
read -p "Whitelist IPs : " WHITELIST_RAW
# normalize: ganti koma jadi spasi, lalu split ke array
WHITELIST=${WHITELIST_RAW//,/ }
WHITELIST_ARR=($WHITELIST)
if [[ ${#WHITELIST_ARR[@]} -eq 0 ]]; then
    WHITELIST_ARR=("127.0.0.1")   # default kalau kosong
fi

# --------------- 5. Show summary & confirm ----------------------------
echo "=========================================="
echo " CONFIGURATION SUMMARY"
echo "=========================================="
if [[ "$VER" == "2c" ]]; then
    echo "SNMPv2c community = $COMM"
    echo "whitelist IPs     = ${WHITELIST_ARR[*]}"
else
    echo "SNMPv3 user       = $USER"
    echo "auth protocol     = $AUTH_PROT"
    echo "privacy protocol  = $PRIV_PROT"
    echo "whitelist IPs     = ${WHITELIST_ARR[*]}"
fi
echo "=========================================="
read -p "Apply this configuration? (y/N) : " CONF
[[ ! "$CONF" =~ ^[Yy]$ ]] && { echo "Cancelled."; exit 0; }

# --------------- 6. Generate config file ------------------------------
CFG="/etc/snmp/snmpd.conf"
cp -f $CFG ${CFG}.bak.$(date +%s) 2>/dev/null || true

cat > $CFG <<'TEMPLATE'
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
# agentaddress  127.0.0.1,[::1]

###########################################################################
# SECTION: Access Control Setup

# Views  (system + hrSystem groups only)
view   systemonly  included   .1.3.6.1.2.1.1
view   systemonly  included   .1.3.6.1.2.1.25.1

# SNMPv2c / v3 will be inserted below
includeDir /etc/snmp/snmpd.conf.d
###########################################################################
# DYNAMIC PART INSERTED BY SCRIPT – DO NOT EDIT MANUALLY BELOW
###########################################################################

TEMPLATE

if [[ "$VER" == "2c" ]]; then
    # hapus baris v3 bawaan, insert v2 per-IP
    sed -i '/^# createUser/d; /^# rouser/d' $CFG
    for ip in "${WHITELIST_ARR[@]}"; do
        echo "rocommunity $COMM $ip -V systemonly" >> $CFG
    done
    echo "rocommunity6 $COMM ::1/128 -V systemonly" >> $CFG
else
    # hapus baris v2 bawaan, insert v3 per-IP
    sed -i '/^rocommunity/d; /^rocommunity6/d' $CFG
    echo "createUser $USER $AUTH_PROT \"$AUTH_PASS\" $PRIV_PROT \"$PRIV_PASS\"" >> $CFG
    for ip in "${WHITELIST_ARR[@]}"; do
        echo "rouser $USER authpriv -V systemonly $ip" >> $CFG
    done
fi

# --------------- 7. Start / enable service ----------------------------
systemctl enable snmpd
systemctl restart snmpd
echo "SNMP service started/restarted."

# --------------- 8. Test with snmpwalk & log --------------------------
echo "Running snmpwalk test ..."
{
    echo "==== $(date)  SNMPWALK TEST ===="
    # coba dari IP pertama dalam daftar
    TEST_IP=${WHITELIST_ARR[0]}
    if [[ "$VER" == "2c" ]]; then
        snmpwalk -v2c -c "$COMM" "$TEST_IP" 1.3.6.1.2.1.1.1.0
    else
        snmpwalk -v3 -u "$USER" -l authPriv \
                 -a "$AUTH_PROT" -A "$AUTH_PASS" \
                 -x "$PRIV_PROT" -X "$PRIV_PASS" \
                 "$TEST_IP" 1.3.6.1.2.1.1.1.0
    fi
} >> "$LOG" 2>&1

if [[ $? -eq 0 ]]; then
    echo "snmpwalk SUCCESS. Full log saved to $LOG"
else
    echo "snmpwalk FAILED. Inspect $LOG"
fi
