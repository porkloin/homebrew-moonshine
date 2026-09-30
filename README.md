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

This installs the udev rules (`/dev/uinput`, `/dev/uhid` for gamepad emulation), the `moonshine@.service` systemd unit, the `moonshine` group (sysusers) and polkit rule for the sleep inhibitor, and the Vulkan WSI layer manifest, and enables and starts `moonshine@$SUDO_USER.service` and turns on user lingering.

To remove everything it set up:

```sh
sudo moonshine-setup-system uninstall
```

## Updating the formula for a new moonshine release

1. Bump `url` and `version` in `Formula/moonshine.rb` to the new release tag.
2. Update `sha256` to match the new `moonshine-vX.Y.Z-linux-amd64.tar.zst` asset.
3. If the release tarball's internal layout changed (`bin/`, `lib/`, `share/moonshine/*`),
   update `install` to match.

## Updates

`.github/workflows/bump.yml` checks [hgaiser/moonshine releases](https://github.com/hgaiser/moonshine/releases) daily. When there's a new release, it:
1. points the formula at it (`scripts/bump-formula.sh`),
2. installs and tests it on Linux Homebrew,
3. commits to `main`.

A failed run (you get GitHub's failure email) means the bump needs a human. There are two likely causes:

- **Tarball layout changed.** The release added or removed files compared to `scripts/release-files.txt`, e.g. a new systemd, udev or sysusers file the setup script should install. Update the formula or `scripts/moonshine-setup-system.sh`, then run `scripts/bump-formula.sh vX.Y.Z --accept-layout` and commit.
- **Install or test broke.** For example, a path the formula `inreplace`s moved upstream.

You can also run it by hand: Actions → Bump moonshine → Run workflow (optionally with a tag), or locally with `scripts/bump-formula.sh`.
