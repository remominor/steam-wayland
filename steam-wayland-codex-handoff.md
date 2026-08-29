# Codex Implementation Handoff: Wayland-First Steam / Moonlight Gaming Container

**Status:** Architecture selected; ready for a clean implementation.

**Primary UX:** Moonlight -> Sunshine.  
**Secondary UX:** Browser-based maintenance attached to the same desktop, added after the Moonlight path is stable.

**Date:** 29 August 2026

---

## 0. Instruction to Codex

Build a **new Wayland-first container**. Do not refactor the existing Xorg display architecture in place and do not copy an entire reference project wholesale.

The implementation target is a **top-level headless Labwc compositor** owned by this container, with Sunshine attached directly through wlroots screencopy. Steam, UMU, Xwayland, games, audio, and a lightweight persistent desktop run inside that same session. A browser maintenance interface may be added later, but it must attach to this desktop rather than own or nest it.

Treat `remominor/docker-steam-headless`, LinuxServer `docker-steam` / `baseimage-selkies`, Prism, Sunshine, and `labwc-headless-docker` as **reference implementations for individual solved problems**, not as architectures to clone.

### Non-negotiable first principles

- Moonlight/Sunshine is the primary streaming and input path.
- Labwc is the **top-level** compositor; no outer Selkies/Smithay compositor.
- Xwayland remains available for Steam, Proton, Wine, and X11 games.
- Do not install an NVIDIA kernel/user driver stack inside the image. Use NVIDIA Container Toolkit runtime injection.
- Preserve the multi-GPU NVIDIA 595 workaround: expose both RTX 3070 GPUs, primary first.
- Avoid all NVIDIA Xorg synthetic-monitor, `ConnectedMonitor`, MetaMode, EDID, and RandR hacks.
- Preserve compatibility fixes from the legacy fork only when their underlying problem still exists in the Wayland design. The migration audit in Section 11 is authoritative.
- Prefer a small, understandable implementation over a feature-complete port of Steam-Headless.

---

## 1. Objective and non-goals

### Objective

Create a reusable Unraid Docker image for headless Linux gaming with:

1. A persistent, lightweight Labwc Wayland desktop that exists immediately after container start.
2. Sunshine capturing that desktop via `capture = wlr` and encoding on NVIDIA NVENC.
3. Moonlight keyboard, mouse, controller, video, and audio working without a browser session.
4. Steam + Proton compatibility through native Wayland where possible and Xwayland where required.
5. UMU as a first-class direct launcher for non-Steam / JC141-style games.
6. Exact or near-exact matching of the Labwc headless output to Moonlight client width, height, and FPS.
7. A persistent game/config layout suitable for Unraid.
8. Optional Flatpak and JC141 compatibility without rediscovering prior container-specific fixes.
9. A later browser maintenance path that attaches to the same compositor rather than nesting another compositor around it.

### Non-goals for v1

- Reproducing the old XFCE/Xorg/noVNC stack.
- Solving NVIDIA's Xorg MetaMode regression.
- HDR support on the headless output.
- A full SteamOS clone.
- Complex per-game automation before the base desktop / input / audio path is stable.
- Tightening every container capability before the functionality baseline is proven.
- Supporting every GPU vendor in the first implementation; architecture should remain portable, but NVIDIA RTX 3070 on Unraid is the validation target.

---

## 2. Validation host and hard constraints

The initial target host is:

- Unraid 7.3.2
- Linux kernel: `6.18.38-Unraid`
- CPU: Ryzen 9 5900X
- NVIDIA driver: **595.99.02**
- Host kernel parameters:
  - `nvidia-drm.modeset=1`
  - `nvidia_drm.fbdev=1`

GPU topology:

| Role | GPU | PCI | DRM render node | UUID |
|---|---|---|---|---|
| Primary gaming/render/encode | RTX 3070 | `00000000:09:00.0` | `/dev/dri/renderD128` | `GPU-cd07fae4-7ed4-c80d-f4df-ec3b5642261e` |
| Secondary | RTX 3070 | `00000000:0a:00.0` | `/dev/dri/renderD129` | `GPU-21fdd467-e589-a334-cd13-5eaceebec5a4` |

### NVIDIA 595 multi-GPU requirement

On NVIDIA 570/580/595 Linux branches, the existing project documented a multi-GPU container regression where exposing only a subset of GPUs could allow CUDA/Xorg but make NVENC fail with `OpenEncodeSessionEx failed: unsupported device (2)`. The validated workaround is to expose **both** GPUs with the desired primary first. [S11]

For this host, v1 should therefore use the equivalent of:

```text
NVIDIA_VISIBLE_DEVICES=GPU-cd07fae4-7ed4-c80d-f4df-ec3b5642261e,GPU-21fdd467-e589-a334-cd13-5eaceebec5a4
NVIDIA_DRIVER_CAPABILITIES=all
```

Do not substitute a single-GPU exposure during functional validation on driver 595.

---

## 3. Empirical findings that drove the redesign

### 3.1 Xorg synthetic-display architecture failed

The custom `remominor/docker-steam-headless` image and a fresh official `josh5/steam-headless:latest` image both reproduced the same failure on NVIDIA 595.99.02:

- Xorg starts and allocates a root framebuffer.
- `xrandr` reports a screen size but **no outputs**.
- NVIDIA Xorg logs an empty `Validated MetaModes:` block followed by `Setting mode "NULL"`.
- Connector-name cycling, `ConnectedMonitor`, custom modes, and valid EDID injection did not produce an active scanout.
- Moving Xorg to the second RTX 3070 reproduced the same failure, ruling out the primary GPU's fbcon / physical connector ownership as the root cause.
- The failure existed on 595.91.07 and 595.99.02; 595.84 was historically known-good.

**Decision:** do not port the synthetic NVIDIA Xorg display machinery. It is legacy baggage, not a requirement for Steam/Proton/Wine.

### 3.2 LinuxServer Wayland stack succeeded on the same driver

A fresh `lscr.io/linuxserver/steam:latest` test on the same host/driver successfully produced:

- Labwc
- Steam started with `--ozone-platform=wayland`
- Xwayland
- NVIDIA GBM/EGL rendering on `/dev/dri/renderD128`
- NVENC initialization on the RTX 3070
- PixelFlux reporting **Zero-Copy path active**

LinuxServer's base also explicitly repaired NVIDIA GBM library linkage at startup. [S12][S13]

This proves NVIDIA 595.99.02 itself can support the required Wayland/GBM/NVENC graphics path on this machine.

### 3.3 Stock Selkies nesting is not the final architecture

The LinuxServer test used two compositor layers:

```text
outer Selkies / Smithay      -> wayland-1
    nested Labwc desktop     -> wayland-0
        WL-1                 -> Steam / Xwayland / games
```

Observed consequences:

- Opening the Selkies browser UI caused Steam to spawn; before that Moonlight could see a black/empty stream.
- Sunshine could capture `wayland-0`, but Moonlight keyboard/mouse did not control the nested Labwc session even after `/dev/uinput` permissions were corrected.
- Direct `wlr-randr --custom-mode ...` against nested Labwc failed.
- Choosing a preset in the Selkies UI changed Labwc's `WL-1` mode, proving the parent compositor owned display sizing.

**Decision:** use LinuxServer as a proof/reference, but remove the outer compositor. Labwc must own its own `HEADLESS-1` output.

### 3.4 Sunshine native wlroots capture is proven

Sunshine 2026.516.143833 was installed temporarily into the LinuxServer test container and launched with:

```ini
capture = wlr
encoder = nvenc
adapter_name = /dev/dri/renderD128
```

with:

```text
XDG_RUNTIME_DIR=/config/.XDG
WAYLAND_DISPLAY=wayland-0
```

Sunshine successfully reported:

```text
[wayland] Found interface: zwp_linux_dmabuf_v1
[wayland] Found interface: zwlr_screencopy_manager_v1
[wlgrab] Selected monitor [Wayland output 1] for streaming
Creating encoder [h264_nvenc]
Creating encoder [hevc_nvenc]
Found H.264 encoder: h264_nvenc [nvenc]
Found HEVC encoder: hevc_nvenc [nvenc]
```

AV1 failed as expected on RTX 3070. After `SYS_NICE` was granted, Sunshine reported the EGL high-priority context successfully. The Web UI was reachable, CSRF origin handling was corrected, Moonlight paired, and video streamed.

This is the strongest proof point: **Wayland capture + NVENC works on the current production driver.** Sunshine itself documents the wlroots capture path in current configuration documentation. [S14]

### 3.5 Renderer policy follow-up

Vulkan is a valid Labwc/wlroots renderer and may be preferable on newer NVIDIA hardware, but renderer startup is not an end-to-end capture test. On Unraid, Vulkan initialized while Sunshine later failed to import an `XR24` compressed DMA-BUF modifier during frame capture. The current image therefore selects GLES2 for NVIDIA and leaves non-NVIDIA renderer selection to wlroots. This is a compatibility policy, not a Sunshine limitation; NVENC and compositor rendering are separate paths.

Revisit a Vulkan-first policy only with a runtime health check that verifies actual `wlr-screencopy` frames and can restart the session with GLES2 after repeated capture failures. The LinuxServer Steam and labwc-headless-docker references do not currently provide that probe: they select GPU/render nodes or set a static renderer, respectively.

---

## 4. Chosen architecture

### 4.1 Logical topology

```text
Unraid + NVIDIA Container Toolkit
        |
        +-- both RTX 3070s exposed (primary first)
        |
Container
  |
  +-- s6 init / service supervision
  |
  +-- container-owned D-Bus session/system services as needed
  |
  +-- seatd / libseat
  |
  +-- Labwc -- TOP-LEVEL headless wlroots compositor
  |     |
  |     +-- HEADLESS-1
  |     +-- Xwayland
  |     +-- persistent lightweight desktop
  |     +-- Steam
  |     +-- UMU / Wine / games
  |     +-- optional Gamescope
  |
  +-- PipeWire + WirePlumber + pipewire-pulse
  |
  +-- Sunshine
  |     +-- capture = wlr
  |     +-- adapter = /dev/dri/renderD128
  |     +-- encoder = nvenc
  |     +-- Moonlight video/audio/input
  |
  +-- optional browser maintenance adapter -> SAME Labwc session
```

### 4.2 Base image recommendation

Preferred starting point:

```dockerfile
FROM ghcr.io/linuxserver/baseimage-debian:trixie
```

or, if the LSIO base introduces unwanted policy, `debian:trixie-slim` plus s6-overlay.

The LinuxServer Debian base is current, Trixie-based, and already provides s6 and the `abc`/PUID/PGID conventions without importing the Selkies compositor stack. [S18]

**Do not use `baseimage-selkies` as the final base** unless Codex can disable and remove the outer Smithay/Selkies display ownership cleanly enough that there is no nested compositor. A clean Debian base is preferred to fighting inherited architecture.

---

## 5. Proposed v1 runtime contract

Start conservative and reduce privileges only after acceptance tests pass.

### Networking

Use **host networking in v1**.

Rationale:

- Sunshine discovery and UDP transport become simpler.
- It matches the previously validated Unraid configuration.
- It removes network namespace behavior as a variable while input/device handling is being validated.

The old project's statement that host networking was *required* was Xorg/udev-hotplug specific. Do not treat it as an eternal Wayland requirement. Once top-level Labwc input is proven, bridge networking can be A/B tested later. [S11]

### Capabilities / security

Initial v1 target:

```text
--runtime=nvidia
--gpus all OR NVIDIA_VISIBLE_DEVICES=<primary>,<secondary>
--cap-add SYS_NICE
--cap-add SYS_ADMIN
--security-opt seccomp=unconfined
--shm-size=2g
```

Use `SYS_ADMIN` initially because the retained Flatpak procfs workaround and FUSE/mount-based JC141 workflows require mount operations. Minimize later if optional features are moved behind feature flags.

Do **not** add `ipc: host` by default. The successful LinuxServer Wayland A/B did not require it. Add it only if a specific game/runtime proves it is needed.

### Required devices

```text
/dev/dri/*
/dev/uinput
/dev/fuse
```

Potentially also expose or materialize `/dev/input/event*` dynamically. See Section 8.

If dynamic input nodes require it, retain an input device cgroup rule equivalent to:

```text
c 13:* rmw
```

### Persistent volumes

Recommended host layout:

```text
/mnt/cache_nvme/appdata/<new-container>/  -> /config
/mnt/user/games_nvme/                     -> /mnt/games
```

`XDG_RUNTIME_DIR`, compositor sockets, PipeWire runtime sockets, and temporary state must be **ephemeral** and live under `/run` or another tmpfs-like runtime path, not `/config`.

---

## 6. NVIDIA runtime normalization

### 6.1 Do not install NVIDIA drivers in the image

The host's NVIDIA runtime must inject the matching libraries. This was a core design rule in the legacy fork and remains correct. [S11]

### 6.2 Primary render/encode selection

Make the primary node explicit:

```text
DRINODE=/dev/dri/renderD128
DRI_NODE=/dev/dri/renderD128
```

Those names come from LinuxServer and can be renamed in the new project, but the implementation must have one explicit render/encode selector rather than relying on first-device enumeration.

### 6.3 Retain LinuxServer's NVIDIA userspace normalization

Study and selectively port the NVIDIA portion of LinuxServer `baseimage-selkies` `init-video/run`. [S13]

Important behaviors worth retaining:

1. Dynamic `/dev/dri` numeric-GID mapping to the runtime user.
2. Create an NVIDIA OpenCL ICD if runtime injection omitted it.
3. Create an NVIDIA Vulkan ICD if omitted.
4. Create GLVND EGL vendor JSON if omitted.
5. **Repair NVIDIA GBM linkage** when `nvidia-drm_gbm.so` exists in a runtime-injected path such as `/usr/lib64/gbm` but not in the Debian loader's normal GBM path.
6. Run `ldconfig` after repair.

This is not theoretical: the LinuxServer test logged `**** Fixing GBM library linkage ****`, then successfully used NVIDIA Wayland/NVENC zero-copy. In the old Steam-Headless environment, the same class of GBM path mismatch had to be fixed manually.

### 6.4 NVIDIA validation checks at startup

Log, but do not overcomplicate startup:

```text
nvidia-smi
ls -l /dev/dri
ldconfig -p | grep -E 'nvidia|EGL|GLX|encode'
find known gbm paths -name nvidia-drm_gbm.so
```

Fail startup if the configured render node does not exist or if Sunshine cannot initialize NVENC when `encoder=nvenc` is required.

---

## 7. Labwc / Wayland session lifecycle

### 7.1 Labwc must be top-level

Launch Labwc directly with a headless backend. Reference implementations use patterns such as:

```text
LIBSEAT_BACKEND=seatd
WLR_BACKENDS=headless,libinput
WLR_RENDERER=vulkan
SEATD_VTBOUND=0
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=labwc
WAYLAND_DISPLAY=wayland-0
```

`labwc-headless-docker` is a useful container reference for this topology, though it is Arch-based and should not be copied wholesale. [S17]

Prism is a stronger behavioral reference: it launches Labwc directly on `WLR_BACKENDS=headless`, creates `HEADLESS-1`, runs Xwayland, sets the exact client mode, and captures that output directly with wlroots screencopy. [S15]

### 7.2 Persistent desktop behavior

The compositor and desktop must start when the container starts, independent of Sunshine clients and independent of browser clients.

Moonlight's **Desktop** entry should immediately show something useful:

- wallpaper
- small panel or status bar
- app launcher
- terminal
- file manager
- Steam launcher

Suggested lightweight pieces: Labwc + sfwbar/Waybar + foot + Thunar + fuzzel/rofi-wayland + swaybg. Keep the list small.

### 7.3 Xwayland

Xwayland is mandatory for compatibility. Do not remove it in pursuit of a "pure Wayland" image. Steam, Proton/Wine and many games still depend on X11 paths. Prism explicitly treats Xwayland as required for headless Steam. [S15]

### 7.4 Dynamic output mode

The owned output should be `HEADLESS-1` and scale 1 by default.

When Sunshine launches a stream, use:

```text
SUNSHINE_CLIENT_WIDTH
SUNSHINE_CLIENT_HEIGHT
SUNSHINE_CLIENT_FPS
```

to set the exact output mode, for example conceptually:

```bash
wlr-randr --output HEADLESS-1 \
  --custom-mode "${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}@${SUNSHINE_CLIENT_FPS}Hz" \
  --scale 1
```

Do not port the legacy `xrandr` modeline generator from `sunshine-run`; replace it with wlroots output management. [S10]

The implementation must handle failure safely: keep a known-good default (e.g. 1920x1080@60) and log whether client-exact mode was applied.

---

## 8. Sunshine integration and input architecture

### 8.1 Sunshine baseline config

Seed a persistent config with at least:

```ini
capture = wlr
encoder = nvenc
adapter_name = /dev/dri/renderD128
system_tray = disabled
```

Do not set an output name until the compositor is known. Once top-level Labwc is stable, the expected output is `HEADLESS-1`.

### 8.2 Sunshine package installation

Retain the legacy project's **build-time postinst suppression** concept. [S1]

The official Debian Sunshine package runs post-install actions that try to:

- invoke `modprobe`
- reload udev rules
- poke `/sys/.../uinput/uevent`
- set capabilities

Those live-host actions are inappropriate during Docker image build and generated harmless errors during the live test installation. During image build, shadow `modprobe` and `udevadm` with no-op helpers (or otherwise suppress those postinst host operations), install the official package, then explicitly configure capabilities/runtime requirements in a controlled way.

Pin the release and verify a checksum in reproducible builds.

### 8.3 CSRF origin handling

Current Sunshine protects state-changing Web UI requests with CSRF origin checks. The old fork already has useful startup logic around `SUNSHINE_CSRF_ALLOWED_ORIGINS`. [S9][S11]

Retain a simple environment override such as:

```text
SUNSHINE_CSRF_ALLOWED_ORIGINS=https://tower.local:47990,https://10.0.0.20:47990
```

Do not rewrite a user-saved explicit setting on every start.

### 8.4 Dynamic device GID mapping - retain and improve

The legacy `10-setup_user.sh` iterates `/dev/uinput`, `/dev/input/event*`, and `/dev/dri/*`, detects numeric GIDs, creates a matching group name when needed, and adds the runtime user to those groups. [S3]

**Retain this behavior.** It exactly addresses the recent test where `/dev/uinput` was mode 0660, root:GID 71, while Debian's named `input` group had a different GID.

Preferred policy:

- join the device's **actual numeric GID**;
- do not assume the container's `input`, `video`, or `render` group IDs match the host;
- do not use blanket `chmod 0666` except as an explicit diagnostic fallback.

### 8.5 Dynamic `/dev/input` event nodes - retain the underlying fix

The legacy dumb-udev fallback handles a real Docker edge case: a Sunshine-created input device may appear in `/sys/class/input/.../dev` while the corresponding `/dev/input/event*` node is absent inside the container's private `/dev`. It then creates the missing character device from the sysfs major/minor. [S5]

For the new architecture:

- **retain the ability to materialize missing event nodes** or solve it by an equivalent cleaner mechanism;
- do not retain the Xorg restart behavior;
- do not assume uinput success implies Labwc/libinput can see the generated event node.

Acceptance diagnostics after a Moonlight client connects should correlate:

```text
/sys/class/input/*/device/name
/sys/class/input/*/dev
/dev/input/event*
```

### 8.6 Input strategy decision tree

First attempt the simplest top-level model:

```text
Sunshine uinput -> /dev/input/event* -> libinput -> top-level Labwc
```

using `WLR_BACKENDS=headless,libinput`, seatd, correct device nodes, and numeric-GID permissions.

If keyboard/mouse injection still fails even with a top-level compositor, adopt a **small Wayland input bridge** modeled on Prism rather than nesting another compositor. Prism's bridge connects directly to the owned Labwc socket and creates wlroots virtual pointer/keyboard devices; controllers remain direct uinput devices. [S15]

Do not fork Sunshine unless necessary. Prefer a separate bridge process that uses public Wayland protocols.

---

## 9. Audio architecture

Prefer:

```text
PipeWire + WirePlumber + pipewire-pulse
```

rather than the old standalone PulseAudio daemon.

### v1 target

Create a predictable virtual stream sink and route game/desktop audio to it. Sunshine should capture that sink/monitor. Because this is a headless gaming container, there is no need to preserve local-speaker playback unless a future use case requires it.

### JC141 / bubblewrap compatibility to test

The legacy fork contains a specific PulseAudio fix for JC141 bubblewrap namespaces:

```ini
enable-shm = no
enable-memfd = no
```

The comment explains that Pulse shared-memory transports can fail across bubblewrap IPC/mount namespaces and can prevent audio or some games from initializing. [S7]

Do **not** blindly port the entire old PulseAudio setup. Instead:

1. Implement PipeWire + pipewire-pulse.
2. Test a representative JC141/bubblewrap game.
3. If the same memfd/shared-memory failure occurs, retain an equivalent socket-only Pulse compatibility configuration for sandboxed clients.

Prism's dedicated PipeWire sinks and loopback routing are a useful later reference if per-session audio isolation becomes desirable. [S15]

---

## 10. Steam, UMU, JC141, Gamescope, and Flatpak

### 10.1 Steam

Use the current LinuxServer `docker-steam` Dockerfile as the reference for:

- Debian Trixie i386 graphics/runtime packages;
- official Steam `.deb` installation;
- Steam wrapper behavior;
- UMU package installation. [S12]

Useful legacy behaviors to adapt, not blindly copy:

- persistent Steam home/config;
- seed a games library under `/mnt/games`;
- optional unattended first Steam bootstrap (`STEAM_AUTO_INSTALL`); [S1][S8]
- optional Steam autostart vs explicit Sunshine app launch.

Do not port XFCE-only autostart or `MODE=primary/secondary` logic.

### 10.2 UMU

Install UMU from the current Debian 13 package release, following LinuxServer's current package pattern. [S12][S16]

UMU is first-class, not merely a helper for Steam. v1 acceptance must include a direct Windows game launch such as:

```text
umu-run --config /config/games/example.toml
```

The config/prefix/game storage must live on persistent mounts.

### 10.3 JC141 compatibility - retain core runtime support

The legacy Dockerfile added the following specifically for JC141-style images: [S1]

- `fuse3`
- `fuse-overlayfs`
- `bubblewrap`
- PipeWire libraries including i386
- Wine staging / winetricks
- pinned DwarFS binaries

Retain the **FUSE + bubblewrap + DwarFS capability set** in the new project because direct JC141/non-Steam use is a target feature.

Wine packaging should be re-evaluated: UMU/Proton should be preferred for ordinary Windows games, but keep Wine staging if a representative JC141 title requires the system Wine path.

Pass `/dev/fuse` into the container.

### 10.4 Gamescope

Gamescope is desirable but not required to prove the compositor architecture. Install it from Trixie backports if dependency impact is acceptable, but defer global wrapper policy until v1 Moonlight/input/audio passes. The old image already used `gamescope/trixie-backports`. [S1]

Do not make Gamescope another always-on nesting layer around the desktop. Use it per-game or for explicitly selected Steam/console-style sessions.

### 10.5 Flatpak - retain the procfs workaround if Flatpak is enabled

This is an important legacy fix that **must not be lost**.

The old `80-configure_flatpak.sh` explains the underlying problem: Docker masks / makes several paths below `/proc` read-only, and NVIDIA Container Toolkit can add a submount at `/proc/driver/nvidia/params`. Those nested mounts can prevent Flatpak's unprivileged bubblewrap process from mounting the private procfs required by its PID namespace. [S2][S11]

The validated startup workaround is:

```bash
mount -t proc -o nosuid,nodev,noexec proc /proc
```

inside the container's mount namespace.

**Decision:**

- If Flatpak is included in v1, retain this startup remount and retain `SYS_ADMIN`.
- If Flatpak is deferred, implement it as a documented optional module and carry this workaround with the module; do not rediscover it later.
- No `systempaths=unconfined` workaround should be necessary according to the old Unraid documentation. [S11]

Also retain the useful persistence behavior:

- user Flatpak install under `/config` / persistent home;
- user Flathub remote;
- avoid relying on `/var/lib/flatpak` because it is part of the disposable image/container layer. [S2]

The legacy image also sets `bwrap` mode 0755 via `dpkg-statoverride`; retain/test this when Flatpak is enabled. [S1]

---

## 11. Legacy `remominor/docker-steam-headless` migration audit

The new project should **selectively port fixes, not files**.

| Legacy item / fix | Decision | New implementation / rationale |
|---|---|---|
| NVIDIA Xorg generator, `ConnectedMonitor`, MetaModes, EDID, RandR synthetic output | **Discard** | Replaced by top-level Labwc `HEADLESS-1`. The old architecture is the failing component. |
| X11 VNC / noVNC as primary browser path | **Discard / redesign later** | Browser maintenance must attach to the same Labwc desktop, e.g. WayVNC + web adapter later. |
| LinuxServer-style NVIDIA GBM linkage repair | **Retain** | Required class of fix was empirically encountered; selectively port LSIO `init-video/run` NVIDIA normalization. |
| Expose all GPUs on NVIDIA 595, primary first | **Retain for current host** | Avoid known multi-GPU NVENC failure on 595. Re-evaluate after moving to a fixed driver branch. |
| Numeric device-GID mapping for `/dev/uinput`, `/dev/input`, `/dev/dri` | **Retain** | Correctly solves host/container group-ID mismatch; prefer over world-writable devices. |
| `chmod 0666 /dev/uinput` | **Replace** | Use actual host device GID and supplementary group membership. Keep chmod only as debug fallback. |
| real udev vs dumb-udev selection | **Simplify** | Avoid full container udev if possible. Keep a minimal missing-input-node materializer or equivalent. |
| materialize missing `/dev/input/event*` from sysfs major/minor | **Retain concept** | Still relevant to Sunshine uinput in a private `/dev`; remove Xorg restart logic. |
| restart Xorg after Sunshine input hotplug | **Discard** | Xorg is gone. Top-level Labwc must see inputs directly or through a Wayland bridge. |
| Host networking requirement | **Retain for v1, re-test later** | Old reason was Xorg hotplug-specific, but host mode reduces variables and simplifies Sunshine discovery. |
| Flatpak clean `/proc` remount | **Retain when Flatpak enabled** | Required for nested Flatpak/bubblewrap procfs on Docker + NVIDIA runtime. |
| Persistent user Flathub / user Flatpak storage | **Retain** | Avoid disposable system Flatpak state. |
| `bwrap` statoverride 0755 | **Retain/test with Flatpak** | Existing compatibility fix; verify with current Trixie Flatpak. |
| container-owned D-Bus and stable machine-id | **Retain** | Do not bind host system D-Bus. Use a container-owned system/session bus. |
| PulseAudio `enable-shm=no`, `enable-memfd=no` for JC141 bwrap | **Conditional retain** | Prefer PipeWire; reproduce a JC141 game and apply equivalent only if needed. |
| `/dev/fuse`, FUSE3, fuse-overlayfs, bubblewrap, DwarFS | **Retain** | Direct JC141/non-Steam packaged games remain a project goal. |
| Wine staging / winetricks | **Re-evaluate** | Prefer UMU/Proton, retain system Wine only where JC141 needs it. |
| Steam persistent library initialization under `/mnt/games` | **Retain/rewrite** | Useful convenience; remove XFCE assumptions. |
| `STEAM_AUTO_INSTALL` Debian launcher patch | **Retain if still needed** | Useful headless first-run convenience; verify against current Steam packaging. |
| Sunshine package postinst suppression during image build | **Retain** | Avoid live `modprobe`/udev/sysfs actions in Docker build. |
| Sunshine CSRF allowed-origins startup helper | **Retain** | Current Sunshine requires explicit origins for non-default Web UI URLs. |
| Sunshine wait for connected RandR output | **Discard** | Replace with readiness check for Labwc socket + `HEADLESS-1` + screencopy protocol. |
| `sunshine-run` xrandr mode creation | **Replace** | Use `wlr-randr` / wlroots against `HEADLESS-1` using client width/height/FPS. |
| XAUTHORITY placeholder | **Do not port by default** | Test JC141 sandbox scripts. Add a harmless compatibility placeholder only if a launcher requires an existing path under Xwayland. |
| `vm.max_map_count=524288` write from container | **Replace with validation/warning** | Avoid silently mutating host-global sysctl. Document recommended host value if required. |
| Force executable bits after copying overlay | **Retain** | Protect against macOS/SMB/Unraid copies losing executable modes. |
| primary/secondary X11 container socket sharing | **Discard** | Not part of the new single-container Wayland design. |
| Neko stack / old frontend | **Discard from v1** | Browser is maintenance-only and should be redesigned after Moonlight is complete. |
| WOL power manager | **Defer** | Useful later but unrelated to architecture validation. |

Source files behind this audit: [S1]-[S11].

---

## 12. Implementation phases

### Phase 0 - new repository and skeleton

Create a new repository or clean branch, suggested working name `docker-steam-wayland`.

Deliver:

- Dockerfile
- s6 services / init scripts
- compose example for Unraid/NVIDIA
- default Labwc config
- default Sunshine config/apps
- README with exact run requirements
- scripts directory with small single-purpose helpers

Do not copy the old overlay wholesale.

### Phase 1 - compositor proof

Install only what is needed for:

- s6
- seatd/libseat
- Labwc
- wlroots tools / `wlr-randr`
- Xwayland
- NVIDIA runtime normalization
- minimal desktop tools

Acceptance:

- `HEADLESS-1` exists at 1920x1080@60, scale 1.
- desktop exists without Sunshine or browser.
- Vulkan/OpenGL app renders on `/dev/dri/renderD128`.
- Xwayland launches.

### Phase 2 - Sunshine video

Install/configure Sunshine.

Acceptance:

- `capture=wlr`
- discovers `zwlr_screencopy_manager_v1`
- captures `HEADLESS-1`
- H.264 NVENC succeeds
- HEVC NVENC succeeds
- Moonlight Desktop shows desktop before Steam is launched
- no dependency on browser UI

### Phase 3 - input

Pass `/dev/uinput`, map numeric GIDs, and solve dynamic event nodes.

Acceptance:

- Moonlight mouse controls Labwc
- Moonlight keyboard controls Labwc
- controller appears and works in a non-Steam input tester
- controller works in Steam
- no world-writable device requirement

If keyboard/mouse fails after top-level libinput validation, implement the small Prism-style wlroots virtual input bridge.

### Phase 4 - audio

Bring up PipeWire/WirePlumber/pipewire-pulse and a stable stream sink.

Acceptance:

- desktop audio reaches Moonlight
- Steam game audio reaches Moonlight
- no browser dependency
- no audio feedback/duplicate loopback

### Phase 5 - Steam + UMU

Acceptance:

- Steam login and persistent library
- Proton game launch
- UMU direct launch
- controller works in both
- game storage remains under `/mnt/games`

### Phase 6 - JC141 + Flatpak compatibility

Acceptance:

- representative DwarFS/FUSE/bubblewrap title launches
- representative title has audio
- Flatpak app launches without bubblewrap private-proc failure
- persistent user Flatpak install survives container recreation

### Phase 7 - dynamic resolution

Drive `HEADLESS-1` from Sunshine client width/height/FPS.

Acceptance matrix should include at least:

- 1280x720@60
- 1920x1080@60
- 1920x1080@120
- 2560x1440@60/120 as supported by client/encoder

The compositor should return to a defined idle/default mode when a stream ends.

### Phase 8 - secondary browser maintenance

Only after Moonlight is fully functional.

Attach browser remote access to the existing Labwc session. WayVNC is a reasonable first candidate; `labwc-headless-docker` already demonstrates WayVNC in a similar topology. [S17]

Do not create a second compositor to make browser access work.

---

## 13. Acceptance test checklist

### Container / lifecycle

- [ ] Container starts from a clean `/config`.
- [ ] Container recreates without losing Steam, Sunshine credentials/config, UMU prefixes, or user Flatpaks.
- [ ] All long-running services are supervised and shut down cleanly.
- [ ] No service depends on a browser connection.

### GPU / Wayland

- [ ] Both GPUs visible to NVIDIA runtime on driver 595.
- [ ] `/dev/dri/renderD128` is the configured renderer/encoder.
- [ ] NVIDIA GBM backend loads from the expected Debian search path.
- [ ] Labwc owns `HEADLESS-1` directly.
- [ ] Xwayland starts and can run a test X11 application.
- [ ] Scale defaults to 1.

### Sunshine / Moonlight

- [ ] Sunshine discovers `zwlr_screencopy_manager_v1`.
- [ ] H.264 NVENC works.
- [ ] HEVC NVENC works.
- [ ] AV1 absence on RTX 3070 is treated as expected, not a fatal startup condition.
- [ ] Web UI can be opened by LAN IP/hostname with explicit CSRF origin configuration.
- [ ] Moonlight displays desktop immediately.
- [ ] Stream survives Steam launch/exit.

### Input

- [ ] Runtime user has numeric-GID access to `/dev/uinput` and `/dev/input/event*`.
- [ ] Sunshine-created devices visible in sysfs have matching container device nodes.
- [ ] Mouse works in desktop.
- [ ] Keyboard works in terminal.
- [ ] Controller works in an input tester before Steam.
- [ ] Controller works in Steam/Proton.
- [ ] Direct UMU game receives controller input.

### Audio

- [ ] PipeWire graph is stable.
- [ ] Sunshine captures intended sink.
- [ ] Steam audio works.
- [ ] UMU/JC141 audio works.
- [ ] Bubblewrap does not fail due to Pulse memfd/shared-memory assumptions.

### JC141 / Flatpak

- [ ] `/dev/fuse` is usable by the intended runtime path.
- [ ] DwarFS mount/launch succeeds.
- [ ] Bubblewrap launch succeeds.
- [ ] Flatpak user remote/storage persists.
- [ ] Flatpak application launches after clean `/proc` remount.

### Dynamic display

- [ ] Client mode is applied to `HEADLESS-1` before the game launches.
- [ ] Requested FPS is reflected in output mode when supported.
- [ ] Mode failure falls back safely and is logged.
- [ ] Stream teardown restores a known idle mode.

---

## 14. Anti-patterns / things Codex should not do

- Do not add NVIDIA Xorg because a game is X11-only; use Xwayland.
- Do not recreate a synthetic Xorg monitor or modeline stack.
- Do not add Selkies/Smithay as an outer compositor just to get browser streaming.
- Do not hide NVIDIA runtime failures by silently falling back to CPU encoding.
- Do not assume named group IDs such as `input` or `video` match host device GIDs.
- Do not solve uinput permissions with permanent `0666` unless there is no safer alternative.
- Do not bind the host D-Bus socket into the container.
- Do not silently write host-global sysctls during container startup.
- Do not require a browser connection to create/start the desktop.
- Do not make Gamescope the always-on desktop compositor.
- Do not replace current Sunshine with Prism wholesale; use Prism as an architectural reference and borrow the input-bridge concept only if required.
- Do not remove Flatpak procfs handling if Flatpak support is present.
- Do not mix host and container NVIDIA driver versions.

---

## 15. Suggested repository layout

```text
docker-steam-wayland/
├── Dockerfile
├── compose/
│   └── docker-compose.unraid-nvidia.yml
├── root/
│   ├── etc/
│   │   ├── s6-overlay/s6-rc.d/
│   │   │   ├── init-device-permissions/
│   │   │   ├── init-nvidia-runtime/
│   │   │   ├── init-flatpak-proc/        # enabled only with Flatpak support
│   │   │   ├── svc-seatd/
│   │   │   ├── svc-dbus/
│   │   │   ├── svc-pipewire/
│   │   │   ├── svc-labwc/
│   │   │   └── svc-sunshine/
│   │   └── ...
│   └── defaults/
│       ├── labwc/
│       ├── sunshine/
│       └── pipewire/
├── scripts/
│   ├── normalize-nvidia-runtime.sh
│   ├── map-device-gids.sh
│   ├── sync-input-nodes.sh
│   ├── set-headless-mode.sh
│   └── launch-umu-game.sh
├── tests/
│   ├── smoke-gpu.sh
│   ├── smoke-wayland.sh
│   ├── smoke-input.sh
│   ├── smoke-audio.sh
│   └── smoke-flatpak.sh
└── README.md
```

Keep helpers small. Each script should be independently testable from `docker exec`.

---

## 16. Definition of done for Codex's first implementation pass

Codex's first pass is complete when it produces a runnable image and compose file that, on the target Unraid host:

1. Starts top-level headless Labwc with `HEADLESS-1` at 1920x1080@60 scale 1.
2. Provides a persistent visible desktop with no browser connection.
3. Starts Xwayland.
4. Normalizes NVIDIA runtime/GBM and renders on `/dev/dri/renderD128`.
5. Starts Sunshine with `capture=wlr` and NVENC.
6. Moonlight displays the desktop immediately.
7. Mouse and keyboard control the Labwc session.
8. At least one controller works through Moonlight.
9. PipeWire audio reaches Moonlight.
10. Steam can launch and render.
11. UMU is installed and can be invoked.
12. The code contains the retained compatibility hooks described in Section 11, especially device-GID mapping, missing-input-node handling, and optional Flatpak clean-procfs handling.

Do not spend the first pass on visual polish, browser maintenance, WOL, or an automatic game catalog.

---

## 17. Source and reference project index

All references below were reviewed against their current public GitHub state on 29 August 2026 unless noted as session evidence.

### Existing project: `remominor/docker-steam-headless`

**[S1] Current Dockerfile**  
https://github.com/remominor/docker-steam-headless/blob/master/Dockerfile  
Use for: JC141 dependencies, DwarFS/FUSE/bubblewrap, Steam first-run patch, Gamescope packaging, Sunshine package-build workaround, executable-bit hardening. Do not copy Xorg/desktop sections.

**[S2] Flatpak startup compatibility**  
https://github.com/remominor/docker-steam-headless/blob/master/overlay/etc/cont-init.d/80-configure_flatpak.sh  
Use for: clean procfs remount, persistent user Flathub.

**[S3] User/device group mapping**  
https://github.com/remominor/docker-steam-headless/blob/master/overlay/etc/cont-init.d/10-setup_user.sh  
Use for: dynamic numeric-GID mapping across `/dev/uinput`, `/dev/input/*`, `/dev/dri/*`.

**[S4] udev selection/configuration**  
https://github.com/remominor/docker-steam-headless/blob/master/overlay/etc/cont-init.d/30-configure_udev.sh  
Use for: understanding restricted `/sys` and `/run/udev`; replace blanket uinput chmod.

**[S5] dumb-udev / input-node materializer**  
https://github.com/remominor/docker-steam-headless/blob/master/overlay/usr/bin/start-dumb-udev.sh  
Use for: materializing missing `/dev/input/*` from sysfs major/minor. Discard Xorg restart behavior.

**[S6] Container-owned D-Bus setup**  
https://github.com/remominor/docker-steam-headless/blob/master/overlay/etc/cont-init.d/30-configure_dbus.sh

**[S7] JC141 Pulse/bubblewrap compatibility**  
https://github.com/remominor/docker-steam-headless/blob/master/overlay/etc/cont-init.d/50-configure_pulseaudio.sh

**[S8] Steam persistent initialization**  
https://github.com/remominor/docker-steam-headless/blob/master/overlay/etc/cont-init.d/90-configure_steam.sh

**[S9] Sunshine startup / CSRF behavior**  
https://github.com/remominor/docker-steam-headless/blob/master/overlay/usr/bin/start-sunshine.sh

**[S10] Legacy client-resolution wrapper**  
https://github.com/remominor/docker-steam-headless/blob/master/overlay/usr/bin/sunshine-run  
Use only as the behavioral reference for client width/height/FPS; replace all `xrandr` logic.

**[S11] Unraid documentation**  
https://github.com/remominor/docker-steam-headless/blob/master/docs/unraid.md  
Use for: NVIDIA multi-GPU 595 workaround, Flatpak procfs rationale, historical input/network findings.

### LinuxServer

**[S12] LinuxServer `docker-steam` Dockerfile**  
https://github.com/linuxserver/docker-steam/blob/master/Dockerfile  
Use for: current Debian Trixie 32-bit packages, official Steam `.deb`, UMU Debian 13 package installation, ProtonUp-Qt packaging. Do not inherit Selkies nesting.

**[S13] LinuxServer `baseimage-selkies` NVIDIA video init**  
https://github.com/linuxserver/docker-baseimage-selkies/blob/master/root/etc/s6-overlay/s6-rc.d/init-video/run  
Use for: device-GID mapping and NVIDIA OpenCL/Vulkan/EGL/GBM runtime normalization. The GBM linkage fix is particularly important.

**[S18] LinuxServer Debian base image**  
https://github.com/linuxserver/docker-baseimage-debian  
https://github.com/linuxserver/docker-baseimage-debian/blob/master/Dockerfile  
Candidate clean Trixie+s6 base without Selkies display ownership.

### Sunshine / Wayland references

**[S14] Sunshine configuration documentation**  
https://github.com/LizardByte/Sunshine/blob/master/docs/configuration.md  
Use for: current `capture=wlr`, encoder, input, network, CSRF, and application settings.

**[S15] Prism**  
https://github.com/atgehrhardt/prism  
https://github.com/atgehrhardt/prism/blob/master/README.md  
Use for: direct headless Labwc, `HEADLESS-1` client-exact modes, Xwayland ownership, wlroots screencopy, Wayland keyboard/mouse bridge, direct-uinput controllers, PipeWire session concepts. Do not adopt the hard Sunshine fork unless needed.

**[S17] `labwc-headless-docker`**  
https://github.com/XT-Martinez/labwc-headless-docker  
https://github.com/XT-Martinez/labwc-headless-docker/blob/main/Dockerfile  
Use for: container-specific seatd/libseat/headless-Labwc environment and WayVNC pattern. It is Arch-based; translate concepts to Debian.

### Game launcher

**[S16] UMU Launcher**  
https://github.com/Open-Wine-Components/umu-launcher  
Use the current Debian 13 release package and upstream config semantics.

---

## 18. Session evidence summary for future debugging

If a future implementation regresses, compare it to these proven facts from the 29 August 2026 test session:

- NVIDIA 595.99.02 can render a Wayland desktop in-container on `/dev/dri/renderD128`.
- LinuxServer's NVIDIA GBM normalization made the GBM/NVENC path work without changing the host driver.
- Sunshine 2026.516.143833 can discover `zwlr_screencopy_manager_v1` in Labwc and capture through Wayland.
- H.264 NVENC and HEVC NVENC both initialize successfully on RTX 3070.
- AV1 NVENC is unsupported on RTX 3070 and should not be treated as a failure.
- `SYS_NICE` allows Sunshine to use the high-priority EGL context.
- Sunshine Web UI CSRF origins must include the actual LAN URL used to log in.
- `/dev/uinput` can have a host numeric GID that differs from Debian's named `input` group; numeric-GID mapping is required.
- Nested Selkies -> Labwc video can work while Moonlight input does not; do not use that nested architecture as evidence that top-level Labwc input is broken.
- Selkies controlled nested Labwc's resolution; this is why the new compositor must own `HEADLESS-1` directly.

---

## 19. Final architectural decision

Proceed with a **clean Wayland-first implementation**. The old Xorg fork remains a valuable compatibility knowledge base, not the foundation of the new image.

The implementation should optimize for this path:

```text
Moonlight -> Sunshine -> direct wlroots screencopy -> top-level Labwc -> Steam / UMU / games
                         direct NVENC              -> PipeWire audio
                         uinput/libinput or small Wayland input bridge
```

Browser access is a maintenance feature attached later to the same Labwc session.
