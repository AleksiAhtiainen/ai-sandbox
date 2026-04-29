{ lib, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/koski-sandbox-username" "sandbox";
in
{
  users.users.${username} = {
    isNormalUser = true;
    uid = 1000;
    group = "users";
    description = username;
    extraGroups = [ "networkmanager" "wheel" ];
    initialPassword = "changeme";
  };

  networking.hostName = lib.mkDefault "koski-sandbox";
}
