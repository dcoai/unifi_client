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
└── protect_cameras.exs
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

Events and recorded-video export are in progress; see `spec.md` §6.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/unifi>.

