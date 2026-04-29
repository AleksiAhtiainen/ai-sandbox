{ pkgs, ... }:

{
  # Raw 9p share. Files appear with whatever uid/gid the host exposes
  # (e.g. 501/20 on macOS). Mounted to a non-user-facing path so the
  # bindfs layer below is the canonical /mnt/share.
  fileSystems."/run/koskishare" = {
    device = "share";
    fsType = "9p";
    options = [
      "trans=virtio"
      "version=9p2000.L"
      "cache=loose"
      "msize=262144"
      "access=any"
      "rw"
      "nofail"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
    ];
  };

  # bindfs layer that remaps host ownership to the VM user (uid 1000 /
  # gid 100), so files on the share are usable without chown regardless
  # of what the host filesystem reports. Writes from the VM appear on
  # the host as the host user (the QEMU process owner).
  fileSystems."/mnt/share" = {
    device = "/run/koskishare";
    fsType = "fuse.bindfs";
    options = [
      "force-user=1000"
      "force-group=100"
      "create-for-user=1000"
      "create-for-group=100"
      "nofail"
      "x-systemd.requires-mounts-for=/run/koskishare"
      "x-systemd.automount"
      "_netdev"
    ];
  };

  environment.systemPackages = [ pkgs.bindfs ];
}
