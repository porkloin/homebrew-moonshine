class Moonshine < Formula
  desc "Game streaming server using the NVIDIA GameStream / Moonlight protocol"
  homepage "https://github.com/hgaiser/moonshine"
  url "https://github.com/hgaiser/moonshine/releases/download/v0.13.5/moonshine-v0.13.5-linux-amd64.tar.zst"
  sha256 "a0be9f33e137922bc40c0346ec095cafd06997ebe115d44baf311572281bd89d"
  license "BSD-2-Clause"
  version "0.13.5"

  depends_on :linux
  depends_on arch: :x86_64

  # No mesa/libdrm: libgbm and the DRI/KMS drivers have to match the
  # running kernel GPU driver, so they must come from the host, not brew.
  depends_on "libevdev"
  depends_on "libxkbcommon"
  depends_on "opus"
  depends_on "wayland"
  depends_on "patchelf" => :build

  def install
    bin.install "bin/moonshine"
    (lib/"moonshine/vulkan-layers").install "lib/moonshine/vulkan-layers/libmoonshine_wsi.so"

    # Prebuilt binary, so it has no RPATH into the Cellar. --add-rpath
    # (not --set-rpath) so we don't clobber one upstream adds later.
    moonshine_rpath = [Formula["opus"].opt_lib, Formula["libevdev"].opt_lib, Formula["libxkbcommon"].opt_lib].join(":")
    system "patchelf", "--add-rpath", moonshine_rpath, bin/"moonshine"
    system "patchelf", "--add-rpath", Formula["wayland"].opt_lib.to_s, lib/"moonshine/vulkan-layers/libmoonshine_wsi.so"

    inreplace "share/moonshine/moonshine@.service", "/usr/bin/start-moonshine.sh", opt_bin/"start-moonshine.sh"
    inreplace "share/moonshine/VkLayer_moonshine_wsi.json",
              "/usr/lib/moonshine/vulkan-layers/libmoonshine_wsi.so",
              opt_lib/"moonshine/vulkan-layers/libmoonshine_wsi.so"

    inreplace "share/moonshine/start-moonshine.sh", "/usr/bin/moonshine", opt_bin/"moonshine"
    bin.install "share/moonshine/start-moonshine.sh"

    (share/"moonshine").install "share/moonshine/60-moonshine.rules",
                                 "share/moonshine/moonshine-modules.conf",
                                 "share/moonshine/moonshine@.service",
                                 "share/moonshine/VkLayer_moonshine_wsi.json"

    # Root-level host setup (udev rules, systemd unit, Vulkan layer)
    # see scripts/moonshine-setup-system.sh for why it's a separate file.
    bin.install "#{__dir__}/../scripts/moonshine-setup-system.sh" => "moonshine-setup-system"
    (bin/"moonshine-setup-system").chmod 0755
  end

  def caveats
    <<~EOS
      moonshine needs one-time, root-level host setup: udev rules for
      /dev/uinput and /dev/uhid (gamepad emulation), the kernel modules
      those need, the moonshine@.service systemd unit, and the Vulkan WSI
      layer manifest (games won't route frames to moonshine without it).

          sudo #{opt_bin}/moonshine-setup-system

      This also enables and starts moonshine@$SUDO_USER.service and turns on
      user lingering, so it survives reboots without a graphical login. Pass
      --no-enable to only install everything above without starting it.
      Re-run after `brew upgrade moonshine` if the bundled unit/rules/layer
      change. To undo everything: `sudo #{opt_bin}/moonshine-setup-system uninstall`.

      If virtual input devices don't appear, your user may also need the
      `input` group (most desktops already grant it via the udev rule above):

          sudo usermod -aG input $USER   # re-login afterwards
    EOS
  end

  test do
    assert_match "moonshine #{version}", shell_output("#{bin}/moonshine --version")
  end
end
