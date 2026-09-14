# Devbox on Omarchy

Devbox needs Nix. It installs Nix itself the first time you run `ds` (or
`devbox shell`) in a repo with a `devbox.json`, using the Determinate
`nix-installer`. On Omarchy that install can fail because of the Arch `nix`
package.

## Symptom

```text
Nix is not installed. Devbox will attempt to install it.
 INFO nix-installer v2.35.2
Error:
   0: Planner error
   1: Error executing action
   2: Action `create_group` errored
   3: Group `nixbld` existed but had a different gid (959) than planned (30000)
Error: run installer: exit status 1
```

## Cause

The Arch `nix` package (`pacman -S nix`) creates the group `nixbld` and the
users `nixbld01` to `nixbld10` with system ids in the 900 range. Removing the
package with `pacman -Rns nix` deletes the files but leaves the accounts.
`nix-installer` wants to create `nixbld` at gid 30000 and refuses to adopt a
group with a different gid, so it stops.

Check for the leftovers with:

```sh
getent group nixbld
```

If it prints a line with a gid below 30000 and no `/nix` directory exists, the
accounts are stale.

## Fix

Delete the stale accounts, then let devbox install Nix again:

```sh
for i in $(seq -w 1 10); do sudo userdel nixbld$i; done && sudo groupdel nixbld && getent group nixbld || echo "clean"
```

Then, in the repo:

```sh
ds
```

`nix-installer` now creates `nixbld` at gid 30000 and `nixbld1` to `nixbld32`
at uid 30001 and up, starts `nix-daemon`, and devbox continues.

## Pick one Nix

Use the Determinate installer, which devbox drives for you. Do not also install
the Arch `nix` package: both want to own the `nixbld` group, and you end up
back at the error above.

If you want the Arch package instead, install it and enable the daemon before
running devbox, and never run the Determinate installer on that machine:

```sh
sudo pacman -S nix
sudo systemctl enable --now nix-daemon.socket
```

Devbox uses whichever `nix` is on `PATH`.

## Uninstall the Determinate Nix

The installer leaves a receipt, and its own uninstaller removes the daemon,
`/nix`, the accounts, and the shell rc edits:

```sh
/nix/nix-installer uninstall
```
