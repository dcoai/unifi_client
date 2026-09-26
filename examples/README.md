# Examples

Twelve scripts, one per public area of the library. Each is a single file
you can copy out and run — no project, no build — because an example you
have to assemble is one nobody runs.

```bash
UNIFI_HOST=udmpro.lan UNIFI_USER=admin UNIFI_PASS=secret elixir examples/device_list.exs
```

Every script takes `--help` and prints its usage without reaching the
network, so you can read what one wants before you give it credentials.

## The Network API — a console on your LAN

| Script | Shows | Module |
|---|---|---|
| `list_sites.exs` | the sites a console holds | `UnifiClient.API.Sites` |
| `device_list.exs` | adopted devices, their model, state and uptime | `UnifiClient.API.Devices` |
| `device_poe.exs` | switching PoE on and off, per port | `UnifiClient.API.Devices` |
| `client_list.exs` | connected and known clients, filtered by IP, CIDR, MAC or pattern | `UnifiClient.API.Clients` |
| `network_config.exs` | wireless networks and LANs | `UnifiClient.API.Networks` |
| `firewall_rules.exs` | firewall rules and port forwards | `UnifiClient.API.Firewall` |
| `statistics.exs` | hourly and daily traffic, DPI categories, speed tests | `UnifiClient.API.Statistics` |

## Protect — the video application on a UniFi OS console

| Script | Shows | Module |
|---|---|---|
| `protect_cameras.exs` | the cameras, and a snapshot from one | `UnifiClient.Protect.Cameras` |
| `protect_recordings.exs` | what was recorded in a window, with thumbnails and heatmaps | `UnifiClient.Protect.Events` |
| `protect_watch.exs` | the live update stream, as it happens | `UnifiClient.Protect.WebSocket` |
| `protect_export.exs` | recorded video out of one camera or several, as MP4 | `UnifiClient.Protect.Video` |

## The Cloud API — Ubiquiti's Site Manager

| Script | Shows | Module |
|---|---|---|
| `cloud_sites.exs` | hosts on the account, their sites, devices and clients | `UnifiClient.Cloud.*` |

## Credentials

The Network and Protect scripts read three variables, and never print them:

| Variable | |
|---|---|
| `UNIFI_HOST` | the console's hostname or IP — a device on your LAN |
| `UNIFI_USER` | a **local** console account (not a Ubiquiti SSO login), without MFA |
| `UNIFI_PASS` | its password |

Optional, where a script says so: `UNIFI_SITE` (default `default`) and
`UNIFI_TYPE` (`udm_pro` or `controller`, default `udm_pro`). Protect needs
neither — it only exists on UniFi OS consoles, and has no sites.

`cloud_sites.exs` is the exception: the Site Manager API authenticates with
`UNIFI_API_KEY`, generated at unifi.ui.com under your account settings, and
reaches consoles through Ubiquiti rather than over your LAN.

Every script passes `verify_ssl: false`, because a console ships with a
self-signed certificate. Consider that before pointing one at anything but
your own network.

## Running against the released package

The scripts install the library from this checkout:

```elixir
Mix.install([{:unifi_client, path: Path.expand("..", __DIR__)}])
```

To run one against what is published instead, change that line to:

```elixir
Mix.install([{:unifi_client, "~> 0.2"}])
```

## What the examples do not do

`UnifiClient.API.Networks` and `UnifiClient.API.Firewall` can create,
update, enable, disable and delete; `Protect.Video` can pull hours of
footage. The scripts here read, and point at the module documentation for
the rest — an example that changed a firewall because someone ran it to see
what it did would not be much of an example.
