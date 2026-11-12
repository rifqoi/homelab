#!/usr/bin/env bash

set -euo pipefail

# This watchdog is deliberately host-local. Atlas does not currently have a
# Kubernetes kubeconfig, and a broken Talos guest cannot be trusted to report
# its own health. A QEMU process stuck in D state for several minutes is a
# stronger signal than an application probe failure and is safe to recover by
# rebooting the affected worker guest.

state_dir="${STATE_DIRECTORY:-/var/lib/atlas-talos-vm-watchdog}"
d_state_threshold_seconds="${ATLAS_VM_D_STATE_THRESHOLD_SECONDS:-180}"
reboot_cooldown_seconds="${ATLAS_VM_REBOOT_COOLDOWN_SECONDS:-1800}"

mkdir -p "$state_dir"
umask 077

# Prevent overlapping timer invocations from racing on the same domain.
exec 9>"$state_dir/lock"
flock -n 9 || exit 0

log() {
  logger -t atlas-talos-vm-watchdog -- "$*"
}

read_state() {
  local file="$1"
  watchdog_state=""
  d_state_since=0
  last_reboot=0

  if [ -r "$file" ]; then
    read -r watchdog_state d_state_since last_reboot < "$file" || true
    case "$d_state_since" in
      ''|*[!0-9]*) d_state_since=0 ;;
    esac
    case "$last_reboot" in
      ''|*[!0-9]*) last_reboot=0 ;;
    esac
  fi
}

write_state() {
  local file="$1"
  local temporary_file="${file}.tmp"

  printf '%s %s %s\n' "$watchdog_state" "$d_state_since" "$last_reboot" > "$temporary_file"
  mv "$temporary_file" "$file"
}

reboot_worker() {
  local domain="$1"

  log "$domain: QEMU main process has been in D state for ${d_state_threshold_seconds}s; requesting guest-agent reboot"
  last_reboot="$now"
  write_state "$state_file"

  if timeout 45 virsh -c qemu:///system reboot "$domain" --mode agent; then
    log "$domain: guest-agent reboot requested"
    return 0
  fi

  log "$domain: guest-agent reboot failed; requesting ACPI reboot"
  if timeout 45 virsh -c qemu:///system reboot "$domain" --mode acpi; then
    log "$domain: ACPI reboot requested"
    return 0
  fi

  log "$domain: automatic reboot failed; leaving the guest untouched for manual recovery"
  return 1
}

now=$(date +%s)
reboot_requested=0

while IFS= read -r domain; do
  [ -n "$domain" ] || continue

  state_file="$state_dir/${domain}.state"
  domain_state=$(virsh -c qemu:///system domstate "$domain" --reason 2>/dev/null || true)
  if [[ "$domain_state" != running* ]]; then
    rm -f "$state_file"
    continue
  fi

  pid=$(pgrep -f -- "-name guest=${domain}," | head -n 1 || true)
  if [ -z "$pid" ]; then
    log "$domain: libvirt reports running but its QEMU process was not found"
    continue
  fi

  process_state=$(ps -o stat= -p "$pid" 2>/dev/null | awk '{print substr($1, 1, 1)}' || true)
  read_state "$state_file"

  if [ "$process_state" != D ]; then
    rm -f "$state_file"
    continue
  fi

  if [ "$watchdog_state" != D ] || [ "$d_state_since" -eq 0 ]; then
    watchdog_state=D
    d_state_since="$now"
    write_state "$state_file"
    log "$domain: QEMU process entered D state; starting confirmation window"
    continue
  fi

  if [ "$((now - d_state_since))" -lt "$d_state_threshold_seconds" ]; then
    continue
  fi

  if [ "$last_reboot" -gt 0 ] && [ "$((now - last_reboot))" -lt "$reboot_cooldown_seconds" ]; then
    log "$domain: still in D state but reboot cooldown is active"
    continue
  fi

  reboot_worker "$domain" || true
  reboot_requested=1
  break
done < <(virsh -c qemu:///system list --all --name | grep -E '^talos-prod-cluster-workers-[[:alnum:]-]+$' || true)

if [ "$reboot_requested" -eq 1 ]; then
  log "worker recovery action completed; Kubernetes readiness will be verified by monitoring"
fi
