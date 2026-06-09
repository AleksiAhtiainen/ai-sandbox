{ pkgs, ... }:

{
  environment.systemPackages = [
    pkgs.yed
  ];
}
