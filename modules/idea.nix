{ unstablePkgs, ... }:

{
  environment.systemPackages = [
    unstablePkgs.jetbrains.idea  # IU 2026.1 from nixos-unstable; needs UTM display set to virtio-gpu-pci (no -gl) to render properly
    # jetbrains-toolbox
  ];

  # JetBrains' launcher reads this file if it exists, otherwise falls back to
  # built-in defaults — so pointing at the share unconditionally is safe.
  environment.sessionVariables.IDEA_VM_OPTIONS = "/mnt/share/shared-config/idea64.vmoptions";
}
