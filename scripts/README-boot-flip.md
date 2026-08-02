# Armada SD/Internal Boot Flip Helpers

These scripts automate the tested AYN Thor flow for switching between an
internally-installed Armada system and an Armada SD card.

## Internal to SD

Boot internal Armada with the Armada SD card inserted, then run:

```sh
sudo ./scripts/boot-sd-once.sh --now
```

From another machine, without copying the script first:

```sh
ssh -i /Users/lmy/.ssh/id_ed25519_ayn_thor armada@10.0.0.48 \
    'bash -s -- --now' < scripts/boot-sd-once.sh
```

The script arms a temporary systemd shutdown unit. On shutdown, Armada first
regenerates the internal ABL `KERNEL` normally, then the temporary unit renames
it to `KERNEL.armada-disabled`. ROCKNIX ABL then falls through to the SD card.

## SD to Internal

Boot the Armada SD card, then run:

```sh
sudo ./scripts/boot-internal.sh --now
```

From another machine, without copying the script first:

```sh
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null armada@10.0.0.48 'bash -s -- --now' < scripts/boot-internal.sh
```

> [!INFO]
> We add the two options because you likely have added the internal Armada's SSH key to your known hosts, but not the SD card's. This avoids "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!".

If the SD card is a fresh install, you probably don't have "password-free sudo" set up yet. In that case,

```sh
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null scripts/boot-internal.sh armada@10.0.0.48:~/
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null armada@10.0.0.48
# Then, in the SSH session:
sudo ./boot-internal.sh --now
```

Each command would need you to enter the `armada` password.

The stock Armada SD image uses `armada` / `armada` unless you changed it. The
script mounts the internal ROCKNIX ESP, renames `KERNEL.armada-disabled` back to
`KERNEL`, and reboots so ABL chooses the internal install again.

## Safety Checks

`boot-sd-once.sh` refuses to run unless:

- the current `/boot/efi` is not on `mmcblk`;
- internal `/boot/efi/KERNEL` exists;
- `/dev/mmcblk0p1..p3` look like an Armada SD card.

`boot-internal.sh` refuses to run unless:

- the current `/boot/efi` is on `mmcblk`;
- the internal ESP device exists;
- the internal ESP looks like the `ROCKNIX` partition.

On current AYN Thor installs the internal ESP is `/dev/sda18`. Override it with:

```sh
sudo ./scripts/boot-internal.sh --esp /dev/sdXN --now
```
