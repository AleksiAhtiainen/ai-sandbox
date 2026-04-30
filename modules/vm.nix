{ modulesPath, lib, flakeSelf, ... }:

{
  imports = [
    "${toString modulesPath}/profiles/qemu-guest.nix"
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "usbhid"
    "usb_storage"
    "sr_mod"
  ];

  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };

  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  boot.growPartition = lib.mkDefault true;

  virtualisation.diskSize = lib.mkDefault "auto";

  boot.loader.grub = {
    enable = lib.mkDefault true;
    efiSupport = lib.mkDefault true;
    efiInstallAsRemovable = lib.mkDefault true;
    device = lib.mkDefault "nodev";
  };

  environment.etc."nixos".source = flakeSelf;
}
