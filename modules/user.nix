{ lib, ... }:

let
  readOr = path: default:
    if builtins.pathExists path
    then lib.removeSuffix "\n" (builtins.readFile path)
    else default;

  username = readOr "/etc/ai-sandbox-username" "sandbox";
in
{
  users.users.${username} = {
    isNormalUser = true;
    uid = 1000;
    group = "users";
    description = username;
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    # Locked. ai-sandbox-firstboot prompts for a password on tty1 after the rebuild,
    # before GDM ever runs — so no default password ships in the seed.
    initialHashedPassword = "!";
  };

  networking.hostName = lib.mkDefault "ai-sandbox";
}
