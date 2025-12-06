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
└── list_sites.exs
```

each script needs config information specified as environment variables, they can be run like:

```bash
UNIFI_HOST=udmpro.my_net UNIFI_USER=admin UNIFI_PASS=secret elixir examples/device_list.exs
```

all the scripts will take a `-h` or `--help` option to give a brief help message.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/unifi>.

