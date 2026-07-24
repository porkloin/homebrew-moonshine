# homebrew-moonshine

A [Homebrew](https://brew.sh) tap for [moonshine](https://github.com/hgaiser/moonshine), a Moonlight-compatible game streaming server for Linux.

## Requirements

- Linux, x86_64
- systemd
- glibc

## Install

```sh
brew install porkloin/moonshine/moonshine
```

## Set up

After installing, run the one-time root-level setup:

```sh
sudo moonshine-setup-system
```

This installs the udev rules (`/dev/uinput`, `/dev/uhid` for gamepad emulation), the `moonshine@.service` systemd unit, and the Vulkan WSI layer manifest, and enables and starts `moonshine@$SUDO_USER.service` and turns on user lingering.

To remove everything it set up:

```sh
sudo moonshine-setup-system uninstall
```

## Updating the formula for a new moonshine release

1. Bump `url` and `version` in `Formula/moonshine.rb` to the new release tag.
2. Update `sha256` to match the new `moonshine-vX.Y.Z-linux-amd64.tar.zst` asset.
3. If the release tarball's internal layout changed (`bin/`, `lib/`, `share/moonshine/*`),
   update `install` to match.
