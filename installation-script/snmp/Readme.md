#Usage in Ansible

- name: Deploy SNMP
  script: install-snmp.sh
  environment:
    SNMP_VERSION: "3"
    SNMPv3_USER: "monUser"
    SNMPv3_AUTH_PASS: "AuthPass123"
    SNMPv3_PRIV_PASS: "PrivPass123"
    SNMP_WHITELIST: "192.168.1.0/24 10.0.0.10"
  register: snmp
  failed_when: snmp.rc != 0
  changed_when: "'OK' in snmp.stdout"
