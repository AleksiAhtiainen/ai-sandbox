{ pkgs, ... }:

let
  script = pkgs.writeShellApplication {
    name = "koski-firstboot";
    runtimeInputs = with pkgs; [ coreutils gnugrep shadow systemd ];
    text = ''
      set -euo pipefail

      src=/mnt/share/shared-config/.host-username

      # Loop until .host-username exists and is a valid Linux username.
      # The user account is locked, so the only path forward is to fix the
      # file on the host — exiting would hand control to getty and block them.
      while :; do
        if [ ! -f "$src" ]; then
          cat <<MSG

  Waiting for $src

  On the host, run:
    echo "\$USER" > ~/koski-share/shared-config/.host-username

  Then press Enter to retry.
MSG
          read -r _ || true
          continue
        fi

        u=$(tr -d '[:space:]' < "$src")
        if ! printf '%s' "$u" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}$'; then
          cat <<MSG

  Invalid username in $src: '$u'
  (must match ^[a-z_][a-z0-9_-]{0,31}$)

  Fix the file on the host, then press Enter to retry.
MSG
          read -r _ || true
          continue
        fi

        break
      done

      printf '%s' "$u" > /etc/koski-sandbox-username
      chmod 0644 /etc/koski-sandbox-username

      arch=$(uname -m)
      case "$arch" in
        aarch64) target=sandbox-aarch64-linux ;;
        x86_64)  target=sandbox-x86_64-linux ;;
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
      esac

      /run/current-system/sw/bin/nixos-rebuild switch --flake "/etc/nixos#$target" --impure

      # Set the login password before GDM ever runs, so no default password
      # ever exists on disk and GDM's first-login keyring is encrypted with
      # the real password from the start.
      echo
      echo "Set a login password for '$u':"
      until passwd "$u"; do
        echo "passwd failed — try again."
      done

      systemctl reboot
    '';
  };
in
{
  systemd.services.koski-firstboot = {
    description = "Personalize VM with host username on first boot";
    after = [ "mnt-share.mount" "network-online.target" ];
    wants = [ "mnt-share.mount" "network-online.target" ];
    before = [ "getty@tty1.service" "display-manager.service" ];
    conflicts = [ "getty@tty1.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "!/etc/koski-sandbox-username";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${script}/bin/koski-firstboot";
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
    };
  };
}
