# steam-wayland

A Wayland-first, headless Linux gaming container for Steam, UMU/Proton, and Sunshine/Moonlight. Labwc owns a virtual output, Sunshine captures it through `wlr-screencopy`, PipeWire provides a dedicated streaming sink, and Xwayland remains available for older games.

The image is currently NVIDIA/amd64 focused. It has been tested locally with an RTX 4070 Ti SUPER and is intended for an Unraid host with two RTX 3070 GPUs.

## Included stack

- Debian Trixie on the LinuxServer.io s6 base image
- Labwc (GLES2 by default for NVIDIA DMA-BUF compatibility), XFCE 4.20 desktop components, Xwayland, PipeWire, WirePlumber, and seatd
- Firefox ESR, Foot and XFCE terminals, Thunar, Mousepad, File Roller, Pavucontrol, and common command-line/system tools
- Sunshine with Wayland capture and NVENC
- Steam plus 32-bit graphics/runtime libraries
- UMU Launcher, DwarFS, FUSE 3, and optional user-scoped Flatpak
- Dynamic `/dev/input/event*` materialization for hot-plugged controllers
- Persistent `/config` and `/mnt/games` mounts

## Local build and test

Requirements are Docker with Buildx, the NVIDIA Container Toolkit, a working NVIDIA Docker runtime, and host devices `/dev/dri`, `/dev/input`, `/dev/uinput`, and `/dev/fuse`. The local and Unraid deployment files also mount `/run/udev` read-only so libinput can discover Sunshine-created virtual keyboard and mouse devices.

```bash
docker buildx build --load -t steam-wayland:local .
docker compose -f compose/docker-compose.local.yml up -d --no-build
docker compose -f compose/docker-compose.local.yml logs -f
```

The local Compose file uses host networking. By default it sets Sunshine's base port to `48989` so it can coexist with a host Sunshine instance using `47989`. Its Web UI is therefore at `https://localhost:48990`. Override this with `SUNSHINE_PORT` in `.env` if needed.

Run the smoke suite against the running container:

```bash
./tests/lint-shell.sh
./tests/smoke-image.sh steam-wayland:local
./tests/smoke-gpu.sh
./tests/smoke-wayland.sh
./tests/smoke-input.sh
./tests/smoke-audio.sh
```

Local state is stored in the ignored `config/` and `games/` directories. Stop the stack with:

```bash
docker compose -f compose/docker-compose.local.yml down
```

## Unraid deployment

GitHub Actions publishes `linux/amd64` images to `ghcr.io/remominor/steam-wayland`. Main builds receive `latest` and `sha-*` tags; `v*` Git tags additionally receive semantic-version tags.

Use either [the NVIDIA Compose file](compose/docker-compose.unraid-nvidia.yml) or import [the Unraid template](unraid/steam-wayland.xml). The checked-in deployment defaults match the intended server:

- Configuration: `/mnt/cache_nvme/appdata/steam-wayland`
- Games: `/mnt/user/games_nvme`
- NVIDIA GPUs: both recorded RTX 3070 UUIDs, primary first
- Render node: `/dev/dri/renderD128`
- Sunshine Web UI: `https://SERVER-IP:47990`

Before starting, verify that the Unraid NVIDIA plugin/container runtime works and that `/dev/uinput`, `/dev/fuse`, and `/dev/dri/renderD128` exist. If DRM numbering or GPU UUIDs changed, edit `DRI_NODE` and `NVIDIA_VISIBLE_DEVICES` first.

For Compose:

```bash
docker compose -f compose/docker-compose.unraid-nvidia.yml pull
docker compose -f compose/docker-compose.unraid-nvidia.yml up -d
```

Open the Sunshine Web UI, create its first administrator account, then pair Moonlight. Credentials, certificates, Steam data, and launcher state persist under `/config`.

## Configuration

Default files are copied only when each configuration directory is first created. After that, files under `/config` are user-owned and image updates do not replace them.

If an existing `/config` was created by an earlier image, remove the `xterm -iconic -title Xwayland-Keepalive ...` line from `/config/labwc/autostart` and change desktop Steam launch commands from `steam -gamepadui` to `steam` in `/config/labwc/rc.xml` and `/config/waybar/config.jsonc` (or apply the equivalent edits in the UI). The Sunshine Steam app remains the intended Big Picture entry. The image preinstalls its Steam host libraries and disables Debian's interactive `steamdeps` helper, so first launch can bootstrap/update Steam without requesting a root password. The `abc` user has Bash as its login shell so Foot opens an interactive terminal instead of immediately exiting.

Important variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PUID` / `PGID` | local `1000:1000`, Unraid `99:100` | Runtime file ownership |
| `NVIDIA_VISIBLE_DEVICES` | `all` locally | GPUs injected by the NVIDIA runtime |
| `DRI_NODE` | `/dev/dri/renderD128` | Vulkan renderer and Sunshine adapter |
| `WLR_RENDERER` | `auto` | NVIDIA automatically uses GLES2 for DMA-BUF compatibility; other GPUs use wlroots auto-selection. Explicit `vulkan`, `gles2`, or `pixman` overrides are supported |
| `WLR_LIBINPUT_NO_DEVICES` | `1` | Allows headless Labwc to start before Sunshine creates virtual input devices; libinput still discovers devices when they appear |
| `XDG_SEAT` | `seat0` | Seat assigned to Labwc and Sunshine input devices |
| `DEFAULT_MODE` | `1920x1080@60` | Fixed virtual desktop resolution and refresh rate |
| `OUTPUT_MODE_POLICY` | `client` | `client` follows the Moonlight client's requested width, height, and FPS; `fixed` uses `DEFAULT_MODE` |
| `SUNSHINE_PORT` | unset in the image | Optional Sunshine base-port override |
| `SUNSHINE_CSRF_ALLOWED_ORIGINS` | unset | Optional trusted Web UI origins |
| `ENABLE_FLATPAK` | `false` | Enables the container procfs workaround and Flathub |

The desktop follows each Moonlight client's requested width, height, and frame rate by default. Set `OUTPUT_MODE_POLICY=fixed` with `DEFAULT_MODE=1920x1080@60` to force a fixed virtual desktop. The compositor is Labwc, while XFCE 4.20 supplies the panel, desktop background/icons, settings, notifications, application finder, and session-managed desktop applications. The desktop Steam button intentionally launches normal Steam/login; the Sunshine Big Picture app supplies `STEAM_ARGS` for gamepad UI mode.

The desktop session does not keep an invisible Xwayland client open. Xwayland starts on demand when Steam or another X11 application launches, so no `Xwayland-Keepalive` window should appear.

Right-clicking the desktop opens XFCE's desktop menu when the XFCE shell is active. Labwc's fallback menu includes “Display Settings” and “Reload Labwc configuration”; the latter reloads `rc.xml`, `menu.xml`, and related files. Headless resolution is controlled by `DEFAULT_MODE` and `OUTPUT_MODE_POLICY`; the XFCE display settings tool can inspect the Wayland output but the policy is authoritative at compositor/Sunshine startup.

### Renderer policy

`WLR_RENDERER` is not a Sunshine requirement; it selects Labwc/wlroots' compositor renderer. This deployment intentionally defaults NVIDIA to GLES2 because Vulkan can initialize successfully and still produce DMA-BUF modifiers that Sunshine's wlroots capture path cannot import (the observed `XR24`/`BLOCK_LINEAR` frame-capture failure). NVENC encoding is independent of this choice.

The reference projects handle this similarly at deployment time: LinuxServer's Steam image uses the PixelFlux/Smithay stack and its automatic GPU option selects a render node, while `labwc-headless-docker` sets Vulkan in its Dockerfile but overrides it to GLES2 in its Compose example. We are not pursuing Vulkan-first auto-detection; use `WLR_RENDERER=vulkan` only as an explicit, host-specific override when it has been verified end to end.

Input follows the container-safe path used by the reference projects: Sunshine creates virtual devices through `/dev/uinput`, while Labwc/libinput discovers them through the mounted `/dev/input` tree and `/run/udev` database. The runtime user is added to each device's actual numeric group ID. If a host has a non-default seat, set `XDG_SEAT` to that seat consistently for the compositor and Sunshine.

To add a UMU game, create its UMU TOML under `/config/games`, then add a Sunshine application whose command is:

```text
/usr/local/bin/launch-umu-game.sh /config/games/example.toml
```

Flatpak is deliberately off by default because its container workaround needs `SYS_ADMIN`. The capability is already present in the supplied deployment files; set `ENABLE_FLATPAK=true` only when needed.

## Security notes

Sunshine's Web UI uses a self-signed certificate on first start. Keep it on a trusted LAN, leave UPnP disabled, and do not publish the host-network ports directly to the internet. The container is not privileged, but gaming, FUSE/Flatpak, realtime scheduling, and dynamic input access require broader capabilities than a typical application container.

## Development

Shell syntax, image content, Compose rendering, and the runtime smoke checks are the main acceptance gates. The implementation plan and design rationale remain in [the original handoff](steam-wayland-codex-handoff.md).

Licensed under the [MIT License](LICENSE).
