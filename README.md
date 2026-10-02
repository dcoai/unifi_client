# UnifiClient

[![Hex.pm](https://img.shields.io/hexpm/v/unifi_client.svg)](https://hex.pm/packages/unifi_client)
[![Docs](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/unifi_client)
[![License](https://img.shields.io/hexpm/l/unifi_client.svg)](https://github.com/dcoai/unifi_client/blob/main/LICENSE)

> Note: this library has worked well for my purposes, but is immature, and may have bugs. Please post an issue if you find any.

An Elixir client for **UniFi Network** and **UniFi Protect** — the two
applications on a UniFi OS console — and for Ubiquiti's **Cloud Site
Manager**.

One authenticated client serves both local applications: Network and Protect
share a console and a login, so a session opened for one works for the other.

| | |
|---|---|
| **Network** | sites, devices (including PoE), clients, wireless and LAN configuration, firewall rules and port forwards, traffic statistics, live events over WebSocket |
| **Protect** | cameras and snapshots, recorded events with thumbnails and heatmaps, MP4 export of recorded video, live updates over Protect's binary WebSocket |
| **Cloud** | hosts, sites, devices and clients through the Site Manager API, with an API key rather than a console login |

Talks to UDM Pro and other UniFi OS consoles, self-hosted controllers
(`type: :controller` — Network only; Protect is UniFi OS), and
`api.ui.com`.

## Installation

```elixir
def deps do
  [
    {:unifi_client, "~> 0.2"}
  ]
end
```

Requires **Elixir 1.20 or newer** — the version this library is built and
tested on.

### What you need

- A console reachable from where the code runs. It is a device on your LAN;
  nothing here goes through Ubiquiti's cloud except the `Cloud` modules.
- A **local** console account — one created on the console itself, not a
  Ubiquiti SSO login — **without MFA**. Give it the least role that can do
  what you need.
- Consoles ship a self-signed certificate, so `verify_ssl: false` is the
  usual setting on a LAN. It means what it says; consider it before pointing
  this at anything that is not your own network.

## Network

```elixir
{:ok, client} =
  UnifiClient.Client.new(
    host: "192.168.1.1",
    username: "admin",
    password: "secret",
    verify_ssl: false
  )

{:ok, client} = UnifiClient.Auth.login(client)

{:ok, sites} = UnifiClient.API.Sites.list(client)
{:ok, devices} = UnifiClient.API.Devices.list(client, "default")
{:ok, active} = UnifiClient.API.Clients.list_active(client, "default")

:ok = UnifiClient.Auth.logout(client)
```

A session that the console has expired is renewed and the call retried, once,
without the caller seeing it — and concurrent callers renew once between them
rather than each starting a login.

```bash
UNIFI_HOST=udmpro.lan UNIFI_USER=admin UNIFI_PASS=secret elixir examples/device_list.exs
```

## UniFi Protect

Protect runs on the same UniFi OS console as Network and uses the same login,
so one authenticated client serves both. (Protect is not available on a
self-hosted `type: :controller`.)

```elixir
{:ok, client} = UnifiClient.Client.new(host: "unvr.local", username: "admin", password: "secret")
{:ok, client} = UnifiClient.Auth.login(client)

{:ok, cameras} = UnifiClient.Protect.Cameras.list(client)
porch = Enum.find(cameras, &(&1["name"] == "Porch"))

# live snapshot as JPEG bytes, or straight to a file
{:ok, jpeg} = UnifiClient.Protect.Cameras.snapshot(client, porch["id"], w: 640)
{:ok, "porch.jpg"} = UnifiClient.Protect.Cameras.snapshot(client, porch["id"], dest: "porch.jpg")
```

Recorded video is exported as MP4, streamed straight to disk. The console
renders the clip on demand, so the call waits roughly as long as the clip is
long (the timeout is derived from the window; pass `timeout:` to override):

```elixir
start = ~U[2026-09-17 08:00:00Z]
finish = DateTime.add(start, 60, :second)
{:ok, "porch.mp4"} = UnifiClient.Protect.Video.export(client, porch["id"], start, finish, "porch.mp4")

# recent motion events and their thumbnails
{:ok, events} = UnifiClient.Protect.Events.list(client, start: start, types: ["motion"])
{:ok, jpeg} = UnifiClient.Protect.Events.thumbnail(client, hd(events)["id"])
```

Live updates arrive over Protect's binary WebSocket as
`{:unifi_protect_event, %{action: action, data: data}}` messages; the
subscription resumes from `lastUpdateId` across reconnects so nothing repeats:

```elixir
{:ok, _ws} = UnifiClient.Protect.WebSocket.start_link(client: client, subscriber: self())

receive do
  {:unifi_protect_event, %{action: %{"modelKey" => "camera", "id" => id}, data: %{"isMotionDetected" => true}}} ->
    IO.puts("motion on #{id}")
end
```

## Cloud

The Site Manager API reaches consoles through Ubiquiti rather than over your
LAN, and authenticates with an API key from unifi.ui.com:

```elixir
{:ok, cloud} = UnifiClient.Cloud.Client.new(api_key: System.fetch_env!("UNIFI_API_KEY"))
{:ok, hosts} = UnifiClient.Cloud.Sites.list_hosts(cloud)
```

## Examples

Twelve runnable scripts, one per public area — **[examples/](https://github.com/dcoai/unifi_client/blob/main/examples)**,
indexed in [examples/README.md](https://github.com/dcoai/unifi_client/blob/main/examples/README.md) with what each shows and
which credential it needs. Each is a single file you can copy out and run:

```bash
UNIFI_HOST=udmpro.lan UNIFI_USER=admin UNIFI_PASS=secret elixir examples/protect_cameras.exs
```

Every script takes `-h`/`--help` and prints its usage without touching the
network, runs from any directory, and prints the reason and exits 1 when a
console cannot be reached or a login is refused.

## Documentation

The API reference is on [HexDocs](https://hexdocs.pm/unifi_client).
[`spec.md`](spec.md) is the library’s specification — what each module is
for, which console endpoints it speaks to, and the rules the implementation
follows.

## Status

Network and Protect are both implemented and covered by the suite; `spec.md`
marks what each module supports. The console's own API is undocumented and
varies by firmware, so responses are returned as the console sends them —
maps with string keys — rather than being remodelled into structs.

## License

MIT — see [LICENSE](https://github.com/dcoai/unifi_client/blob/main/LICENSE).
