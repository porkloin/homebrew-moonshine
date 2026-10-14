#!/usr/bin/env bash
# Machine-level setup for moonshine. Run via sudo.
#   moonshine-setup-system                  # install, enable + start the service
#   moonshine-setup-system --no-enable       # install without starting it
#   moonshine-setup-system uninstall         # remove everything this installed
#
# Paths resolve relative to its own installed location
# instead of being templated in at formula-install time.

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
SHARE_DIR="${SCRIPT_DIR}/../share/moonshine"

RULES_SRC="${SHARE_DIR}/60-moonshine.rules"
RULES_DEST="/etc/udev/rules.d/60-moonshine.rules"
MODULES_SRC="${SHARE_DIR}/moonshine-modules.conf"
MODULES_DEST="/etc/modules-load.d/moonshine.conf"
UNIT_SRC="${SHARE_DIR}/moonshine@.service"
UNIT_DEST="/etc/systemd/system/moonshine@.service"
LAYER_SRC="${SHARE_DIR}/VkLayer_moonshine_wsi.json"
LAYER_DEST="/etc/vulkan/implicit_layer.d/VkLayer_moonshine_wsi.json"
SYSUSERS_SRC="${SHARE_DIR}/moonshine-sysusers.conf"
SYSUSERS_DEST="/etc/sysusers.d/moonshine.conf"
POLKIT_SRC="${SHARE_DIR}/50-moonshine-inhibit-sleep.rules"
POLKIT_DEST="/etc/polkit-1/rules.d/50-moonshine-inhibit-sleep.rules"

# Brew installs under /home/linuxbrew, labeled user_home_t, which systemd may neither execute
# nor follow symlinks through on SELinux-enforcing hosts (the unit fails with 203/EXEC
# "Permission denied"). Label every installed version's bin/ (Cellar/moonshine/<version>/bin)
# and the opt/moonshine symlink the unit's ExecStart goes through as bin_t.
KEG_ROOT=$(dirname "$(dirname "${SCRIPT_DIR}")")
BREW_PREFIX=$(dirname "$(dirname "${KEG_ROOT}")")
OPT_LINK="${BREW_PREFIX}/opt/moonshine"
# shellcheck disable=SC2016 # literal sed pattern, nothing to expand
regex_escape() { printf '%s' "$1" | sed 's/[][\\.*^$()+?{}|]/\\&/g'; }
# semanage rejects specs under an equivalency source (e.g. "/var/home /home" on Fedora
# Atomic, where readlink -f resolves /home to /var/home), so rewrite to the target side.
selinux_equiv_path() {
  local path=$1 type src dst
  type=$(sed -n 's/^SELINUXTYPE=//p' /etc/selinux/config 2>/dev/null)
  while read -r src dst
  do
    [[ -z "${src}" || "${src}" == \#* ]] && continue
    if [[ "${path}" == "${src}" || "${path}" == "${src}"/* ]]
    then
      path="${dst}${path#"${src}"}"
      break
    fi
  done < <(cat "/etc/selinux/${type:-targeted}/contexts/files/file_contexts.subs"{,_dist} 2>/dev/null)
  printf '%s' "${path}"
}
SELINUX_BIN_FCONTEXT="$(regex_escape "$(selinux_equiv_path "${KEG_ROOT}")")/[^/]+/bin(/.*)?"
SELINUX_LINK_FCONTEXT="$(regex_escape "$(selinux_equiv_path "${OPT_LINK}")")"

selinux_enabled() {
  command -v selinuxenabled >/dev/null && selinuxenabled
}

if [[ ${EUID} -ne 0 ]]
then
  echo "must run as root: sudo $0 $*" >&2
  exit 1
fi

# Fail if not running systemd
for tool in systemctl systemd-sysusers udevadm loginctl modprobe
do
  command -v "${tool}" >/dev/null || {
    echo "error: ${tool} not found — this host doesn't look like it's running systemd." >&2
    echo "moonshine's service model (moonshine@.service, udev rules, modules-load.d) requires it." >&2
    exit 1
  }
done

cmd="install"
target_user="${SUDO_USER:-}"
enable=1
for arg in "$@"
do
  case "${arg}" in
    install) cmd="install" ;;
    uninstall) cmd="uninstall" ;;
    --no-enable) enable=0 ;;
    *)
      echo "usage: $0 [install|uninstall] [--no-enable]" >&2
      exit 2
      ;;
  esac
done

case "${cmd}" in
  install)
    install -Dm 0644 "${RULES_SRC}" "${RULES_DEST}"
    install -Dm 0644 "${MODULES_SRC}" "${MODULES_DEST}"
    install -Dm 0644 "${UNIT_SRC}" "${UNIT_DEST}"
    install -Dm 0644 "${LAYER_SRC}" "${LAYER_DEST}"
    install -Dm 0644 "${SYSUSERS_SRC}" "${SYSUSERS_DEST}"
    install -Dm 0644 "${POLKIT_SRC}" "${POLKIT_DEST}"

    # The unit runs with SupplementaryGroups=moonshine; the group must exist first.
    systemd-sysusers "${SYSUSERS_DEST}"
    systemctl reload-or-restart polkit.service 2>/dev/null || true

    udevadm control --reload-rules
    udevadm trigger
    modprobe -q uinput || echo "warning: failed to load uinput module" >&2
    modprobe -q uhid || echo "warning: failed to load uhid module" >&2

    if selinux_enabled
    then
      if command -v semanage >/dev/null
      then
        semanage fcontext -a -t bin_t "${SELINUX_BIN_FCONTEXT}" 2>/dev/null ||
          semanage fcontext -m -t bin_t "${SELINUX_BIN_FCONTEXT}"
        semanage fcontext -a -f l -t bin_t "${SELINUX_LINK_FCONTEXT}" 2>/dev/null ||
          semanage fcontext -m -f l -t bin_t "${SELINUX_LINK_FCONTEXT}"
        restorecon -R "${SCRIPT_DIR}"
        restorecon "${OPT_LINK}"
      else
        echo "warning: SELinux is enabled but semanage is missing; labeling with chcon (lost on a relabel)" >&2
        chcon -R -t bin_t "${SCRIPT_DIR}"
        chcon -h -t bin_t "${OPT_LINK}"
      fi
    fi

    systemctl daemon-reload

    if [[ "${enable}" == "1" && -n "${target_user}" ]]
    then
      loginctl enable-linger "${target_user}"
      systemctl enable --now "moonshine@${target_user}.service"
      echo "done. moonshine@${target_user}.service enabled and started."
    else
      echo "done. enable it yourself with:"
      echo "  sudo systemctl enable --now moonshine@<user>.service"
    fi
    ;;
  uninstall)
    if [[ -n "${target_user}" ]]
    then
      systemctl disable --now "moonshine@${target_user}.service" 2>/dev/null || true
      loginctl disable-linger "${target_user}" 2>/dev/null || true
    fi
    rm -f "${RULES_DEST}" "${MODULES_DEST}" "${UNIT_DEST}" "${LAYER_DEST}" "${SYSUSERS_DEST}" "${POLKIT_DEST}"
    if selinux_enabled && command -v semanage >/dev/null
    then
      semanage fcontext -d "${SELINUX_BIN_FCONTEXT}" 2>/dev/null || true
      semanage fcontext -d -f l "${SELINUX_LINK_FCONTEXT}" 2>/dev/null || true
    fi
    # The moonshine group itself is left in place, like other sysusers-created groups.
    udevadm control --reload-rules
    udevadm trigger
    systemctl daemon-reload
    echo "removed moonshine host-level configuration."
    ;;
  *)
    echo "unknown command: ${cmd}" >&2
    exit 2
    ;;
esac
