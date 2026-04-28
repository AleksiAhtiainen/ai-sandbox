{ lib, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/koski-sandbox-username" "sandbox";
  hostUid = lib.toInt (readOr "/etc/koski-sandbox-uid" "1000");
  hostGid = lib.toInt (readOr "/etc/koski-sandbox-gid" "100");
in
{
  users.groups.${username} = {
    gid = hostGid;
  };

  users.users.${username} = {
    isNormalUser = true;
    uid = hostUid;
    group = username;
    description = username;
    extraGroups = [ "networkmanager" "wheel" ];
    initialPassword = "changeme";
  };

  networking.hostName = lib.mkDefault "koski-sandbox";
}
