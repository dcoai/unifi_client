# UnifiClient

This is an Elixir client for Unifi Networks

This is the first version it is very raw, some things work, some aren't tested.  It is a work in progress.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `unifi` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:unifi, "~> 0.1.0"}
  ]
end
```

## Quick Start

see examples in the examples directory.

they need config information specified as environment variables, they can be run like:

```bash
UNIFI_HOST=udmpro.my_net UNIFI_USER=admin UNIFI_PASS=secret examples/device_list.exs
```
Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/unifi>.

