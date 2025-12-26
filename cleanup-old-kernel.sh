#!/bin/bash
# cleanup-old-kernel.sh
# Remove old kernel packages while keeping the currently running version in RHEL OS Family

# --- Ansible-friendly header ---------------------------------
# If the environment variable ANSIBLE=1 is set, behave like --yes
[[ "${ANSIBLE}" == "1" ]] && FORCE="--yes" || FORCE="$1"
# Redirect stdin to null during Ansible runs to avoid blocking
[[ "${ANSIBLE}" == "1" ]] && exec 0</dev/null
# Ensure we return 0 only when something was removed
CHANGE_MADE=0
# -------------------------------------------------------------

LOG="/var/log/cleanup-kernel.log"
DATE=$(date '+%F %T')
RUNNING=$(uname -r)                 # e.g 4.18.0-240.1.1.el8_3.x86_64
RUNNING_VER=${RUNNING%.x86_64}      # strip .x86_64

echo "========== $DATE  cleanup-old-kernel start ==========" >> "$LOG"

# 1) Show the kernel version in use
echo "1) Currently running kernel: $RUNNING" | tee -a "$LOG"

# 2) List old packages that will be removed
echo "2) Old kernel packages to be REMOVED:" | tee -a "$LOG"
OLD_PKGS=()
for pkg in kernel kernel-core kernel-modules kernel-modules-extra \
           kernel-tools kernel-tools-libs kernel-devel kernel-headers; do
  if rpm -q "$pkg" &>/dev/null; then
    for rpmfile in $(rpm -q "$pkg"); do
      vers=${rpmfile#${pkg}-}     # 4.18.0-xxx.el8.x86_64
      vers=${vers%.x86_64}        # 4.18.0-xxx.el8
      [[ "$vers" != "$RUNNING_VER" ]] && OLD_PKGS+=("$rpmfile")
    done
  fi
done

if [[ ${#OLD_PKGS[@]} -eq 0 ]]; then
  echo "   No old kernel packages found for removal." | tee -a "$LOG"
  exit 2
fi
printf "   %s\n" "${OLD_PKGS[@]}" | tee -a "$LOG"

# 3) Dry-run verification
echo "3) Performing yum remove dry-run ..." | tee -a "$LOG"
yum remove -y "${OLD_PKGS[@]}" --setopt=tsflags=test 2>&1 | tee -a "$LOG"
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
  echo "   Dry-run FAILED, aborting. Check $LOG" | tee -a "$LOG"
  exit 1
fi

# Interactive confirmation (skip with --yes or ANSIBLE=1)
if [[ "${FORCE}" != "--yes" ]]; then
  read -p "Proceed with the removal listed above? (y/N) " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "   Aborted by user." | tee -a "$LOG"; exit 0; }
fi

# 4) Permanent removal and log
echo "4) Removing old packages ..." | tee -a "$LOG"
yum remove -y "${OLD_PKGS[@]}" 2>&1 | tee -a "$LOG"
if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
  echo "   Removal completed." | tee -a "$LOG"
  CHANGE_MADE=1
else
  echo "   Removal FAILED. Check $LOG" | tee -a "$LOG"
  exit 1
fi

# 5) Final verification
echo "5) Final verification – remaining kernel packages:" | tee -a "$LOG"
rpm -qa --queryformat "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" | \
grep -E '^kernel' | sort | tee -a "$LOG"

echo "========== $DATE  cleanup-old-kernel finished ==========" >> "$LOG"

# Signal Ansible whether a change happened
[[ $CHANGE_MADE -eq 1 ]] && exit 0 || exit 2   # 0 = changed, 2 = no old pkg
