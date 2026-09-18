# UnifiClient

This is an Elixir client for Unifi Networks

This is the first version it is very raw, some things work, some aren't tested.  It is a work in progress.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `unifi_client` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:unifi_client, "~> 0.1.2"}
  ]
end
```

## Quick Start

see examples in the `examples/` directory.

```bash
examples
├── client_list.exs
├── device_list.exs
├── device_poe.exs
├── list_sites.exs
├── protect_cameras.exs
└── protect_export.exs
```

each script needs config information specified as environment variables, they can be run like:

```bash
UNIFI_HOST=udmpro.my_net UNIFI_USER=admin UNIFI_PASS=secret elixir examples/device_list.exs
```

all the scripts will take a `-h` or `--help` option to give a brief help message.

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

```bash
UNIFI_HOST=unvr.local UNIFI_USER=admin UNIFI_PASS=secret \
  elixir examples/protect_cameras.exs --snapshot <camera-id> --out porch.jpg
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

```bash
UNIFI_HOST=unvr.local UNIFI_USER=admin UNIFI_PASS=secret \
  elixir examples/protect_export.exs --camera <camera-id> \
    --start 2026-09-17T08:00:00Z --end 2026-09-17T08:01:00Z --out porch.mp4
```

Live event streaming over Protect's WebSocket is planned; see `spec.md` §6.3.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/unifi>.

