{ unstablePkgs, ... }:

{
  environment.systemPackages = [
    unstablePkgs.jetbrains.idea
    # jetbrains-toolbox
  ];
}
