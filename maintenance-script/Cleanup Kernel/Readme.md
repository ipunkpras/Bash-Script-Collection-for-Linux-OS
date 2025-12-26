## 1. Quick Facts
| Item             | Value                                                                        |
| ---------------- | ---------------------------------------------------------------------------- |
| Filename         | `cleanup-old-kernel.sh`                                                      |
| Purpose          | Remove **out-dated kernel** RPMs while **never touching the running kernel** |
| OS Family        | RHEL / CentOS / Alma / Rocky / Oracle Linux 7-9                              |
| Runtime user     | **root** (or sudo)                                                           |
| Ansible friendly | ✅ 100 % non-interactive mode                                                 |
| Exit codes       | `0` = removed / `2` = nothing to do / `1` = error                            |
| Log file         | `/var/log/cleanup-kernel.log`                                                |

## 2. What the script does
1. Detects currently running kernel (uname -r).
2. Lists old kernel RPMs (kernel, kernel-core, modules, tools, devel, headers).
3. Runs dry-run first – aborts on dependency failure.
4. Asks confirmation (unless --yes or Ansible).
5. Removes obsolete packages permanently.
6. Logs every action & performs final verification.
7. Returns Ansible-compatible exit codes.

## 3. Quick manual usage
```bash
chmod +x cleanup-old-kernel.sh
sudo ./cleanup-old-kernel.sh          # interactive confirmation
sudo ./cleanup-old-kernel.sh --yes    # skip prompt
```
or you can run this command for running the script without download the file:
```bash
chmod +x cleanup-old-kernel.sh
sudo ./cleanup-old-kernel.sh          # interactive confirmation
sudo ./cleanup-old-kernel.sh --yes    # skip prompt
```
Example console output:
```
1) Currently running kernel: 4.18.0-240.1.1.el8_3.x86_64
2) Old kernel packages to be REMOVED:
   kernel-4.18.0-1127.el8.x86_64
   kernel-core-4.18.0-1127.el8.x86_64
...
Proceed with the removal listed above? (y/N) y
4) Removing old packages ...
Removal completed.
5) Final verification – remaining kernel packages:
kernel-4.18.0-240.1.1.el8_3.x86_64
kernel-core-4.18.0-240.1.1.el8_3.x86_64
```
## 4. Ansible integration
Copy script to files/ or templates/ then:
```yaml
- name: Remove old kernel packages
  script: cleanup-old-kernel.sh
  environment:
    ANSIBLE: "1"          # non-interactive + auto-confirm
  register: kernel
  failed_when: kernel.rc == 1
  changed_when: kernel.rc == 0          # 0 = packages removed
```
Ad-hoc one-liner:
```bash
ansible all -b -e ANSIBLE=1 -m script -a cleanup-old-kernel.sh
```
## 5. Exit-code summary
| Code | Meaning in Ansible | Description              |
| ---- | ------------------ | ------------------------ |
| 0    | **changed**        | Old kernels were removed |
| 2    | **ok** (no change) | Nothing to remove        |
| 1    | **failed**         | Dry-run or removal error |

## 6. Variables / environment
| Var       | Description                                | Default          |
| --------- | ------------------------------------------ | ---------------- |
| `ANSIBLE` | Set to `1` to auto-confirm                 | (empty → prompt) |
| `--yes`   | First positional arg acts like `ANSIBLE=1` | -                |

## 7. Safety features
- **Never deletes running kernel** (compares uname -r)
- **Dry-run first** – aborts on dependency failure
- **No file-based backup** – old RPMs still available in YUM repo/cache; reinstall with:
```bash
sudo yum install kernel-<old-version>
sudo grub2-set-default <index>
sudo reboot
```

## 8. Troubleshooting
| Symptom                     | Solution                                                                       |
| --------------------------- | ------------------------------------------------------------------------------ |
| `yum: Protected multilib`   | Clean repos, then re-run                                                       |
| `script: command not found` | Copy to target first or use `ansible.builtin.copy` + `ansible.builtin.command` |
| Dry-run fails               | Check YUM lock / broken repo metadata                                          |

## 9. License
Public domain – use at your own risk.
