Universal SNMP v2c / v3 installer & configurator
Ansible-friendly • Multi-IP whitelist • RHEL / CentOS / Ubuntu / SUSE / Arch
## 1. Quick facts
| Item          | Value                       |
|---------------|-----------------------------|
| File name     | install-snmp.sh              |
| Runtime user  | root (or sudo)              |
| Ansible support | ✅ 100 % non-interactive    |
| Exit code     | 0 = success / 1 = failed    |
| Log file      | /var/log/snmp-test.log      |
| OS family     | RHEL, Debian, Ubuntu, SUSE, Arch |

## 2. What the script does
1. Detects distribution and installs correct packages (RHEL → net-snmp net-snmp-utils, Ubuntu → snmpd snmp).
2. Creates idempotent /etc/snmp/snmpd.conf
3. Adds multi-IP whitelist (one line per IP/CIDR)
4. Runs snmpwalk test and logs result
5. Returns proper exit codes for Ansible
6. Never removes running kernel (safety backup .bak.<timestamp>)

## 3. Interactive usage (manual)
Follow on-screen prompts
- Choose version (2c or 3)
- Enter community / v3 credentials
- Supply whitelist IPs/networks (space or comma separated) Example: 192.168.1.10 10.0.0.0/24 2001:db8::/64

#### Run Command
```bash
bash -c "$(curl -fsSLk https://raw.githubusercontent.com/ipunkpras/Bash-Script-Collection-for-Linux-OS/refs/heads/main/installation-script/snmp/snmp-install.sh)"
```

## 4. Ansible usage (fully automated)
Copy script to files/ or templates/ then:
### snmpv3.yaml configuration example
```yaml
- name: Deploy SNMP agent
  script: install-snmp.sh
  environment:
    SNMP_VERSION: "3"
    SNMPv3_USER: "monUser"
    SNMPv3_AUTH_PROT: "SHA"        # optional, default SHA
    SNMPv3_AUTH_PASS: "SuperAuthPass"
    SNMPv3_PRIV_PROT: "AES"        # optional, default AES
    SNMPv3_PRIV_PASS: "SuperPrivPass"
    SNMP_WHITELIST: "192.168.1.0/24 10.50.0.10"
  register: snmp
  failed_when: snmp.rc != 0
  changed_when: "'OK' in snmp.stdout"
```
### snmpv2c.yaml config example
```yaml
environment:
    SNMP_VERSION: "2c"
    SNMP_COMMUNITY: "MySecretCommunity"
    SNMP_WHITELIST: "192.168.1.0/24, 10.0.0.0/16"
```
### Single host (Ansible ad-hoc)
```bash
ansible srv -b -e SNMP_VERSION=2c \
            -e SNMP_COMMUNITY=public \
            -e SNMP_WHITELIST=127.0.0.1 \
            -m script -a install-snmp.sh
```

| Code |                Meaning                       |
|------|----------------------------------------------|
|  0   | Success (service running, snmpwalk passed)   |
|  1   | Failure (package missing, test failed, etc.) |

## 6. Variables reference
| Variable   | Description   | Default   |
|------------|------------|------------|
| SNMP_VERSION | 2c or 3 | (empty → prompt) |
| SNMP_COMMUNITY | community string (v2c) | public |
| SNMPv3_USER | v3 security name | (empty → prompt) |
| SNMPv3_AUTH_PROT | SHA | MD5 | SHA |
| SNMPv3_AUTH_PASS | auth passphrase | (empty → prompt) |
| SNMPv3_PRIV_PROT | AES | DES | AES |
| SNMPv3_PRIV_PASS | privacy passphrase | (empty → prompt) |
| SNMP_WHITELIST | IP/prefix list (space/comma) | 127.0.0.1 |

## 7. Post-install verification
Manual:
```bash
sudo tail /var/log/snmp-test.log
```
Ansible:
```yaml
- name: Show test log
  slurp:
    src: /var/log/snmp-test.log
  register: log
- debug:
    msg: "{{ log.content | b64decode | split('\n') | select | list }}"
```
## 8. Uninstall / rollback
Config backed up to /etc/snmp/snmpd.conf.bak.<timestamp>
Restore:
```bash
sudo systemctl stop snmpd
sudo cp /etc/snmp/snmpd.conf.bak.<ts> /etc/snmp/snmpd.conf
sudo systemctl start snmpd
```
### 9. Security notes
- *Whitelist is enforced* – agent ignores packets from non-listed sources.
- Passphrases should be Vault-encrypted in Ansible:
  ```yaml
  SNMPv3_AUTH_PASS: "{{ vault_snmp_auth_pass }}"
  ```
- Firewall still needs UDP/161 open for remote queries.

## 10. License
Public domain – use at your own risk.
		
		
		
		
		

