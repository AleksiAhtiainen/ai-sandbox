Step 1:

>>>>>>> e6ad9ed (Dokumentointia)
copy your own VM's hardware config here:

    cp /etc/nixos/hardware-configuration.nix ./hardware-configuration.nix

Step 2:

    # TODO, tämä ajaa vielä globaalista hakemistosta
    # sudo nixos-rebuild switch

Puuttuvia ominaisuuksia:

* Ei vielä keksitty, miten saa tiedosto-oikeudet sharessa toimiaan defaulttina oikein. Voi aina ajaa:

    sudo chown -R $USER /mnt/share

