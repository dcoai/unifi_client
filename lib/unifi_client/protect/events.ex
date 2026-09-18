defmodule UnifiClient.Protect.Events do
  @moduledoc """
  Protect events: motion, smart detections, doorbell rings, and the
  images Protect renders for them.

  Times accept a `DateTime` or epoch milliseconds (`UnifiClient.Protect.Time`).

  ## Example

      since = DateTime.add(DateTime.utc_now(), -3600, :second)
      {:ok, events} = UnifiClient.Protect.Events.list(client, start: since, types: ["motion"])

      {:ok, jpeg} = UnifiClient.Protect.Events.thumbnail(client, hd(events)["id"])

  Every function takes a trailing `opts` keyword list; the keys documented
  here are consumed and the rest are passed to `Req.request/2`.
  """

  alias UnifiClient.{Client, Error}
  alias UnifiClient.Protect.{API, Time}

  @doc """
  Lists events, newest first.

  ## Options

    * `:start`, `:end` - window bounds, `DateTime` or epoch ms; either may
      be omitted
    * `:types` - list of event types to include, e.g. `["motion"]`,
      `["smartDetectZone", "ring"]`; omitted means all
    * `:limit` - maximum number of events

  Only the options given are sent; the console applies its own defaults
  for the rest.
  """
  @spec list(Client.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ []) do
    {start, opts} = Keyword.pop(opts, :start)
    {end_, opts} = Keyword.pop(opts, :end)
    {types, opts} = Keyword.pop(opts, :types)
    {limit, opts} = Keyword.pop(opts, :limit)

    path =
      API.with_query("/api/events",
        start: Time.to_ms_or_nil(start),
        end: Time.to_ms_or_nil(end_),
        types: join_types(types),
        limit: limit
      )

    API.get(client, path, opts)
  end

  @doc """
  Fetches the JPEG thumbnail Protect rendered for an event.

  `dest:` is a file path or `:memory` (default).
  """
  @spec thumbnail(Client.t(), String.t(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, Error.t()}
  def thumbnail(%Client{} = client, event_id, opts \\ []) do
    {dest, opts} = Keyword.pop(opts, :dest, :memory)
    API.download(client, "/api/events/#{event_id}/thumbnail", dest, opts)
  end

  @doc """
  Fetches the PNG motion heatmap for an event.

  `dest:` is a file path or `:memory` (default).
  """
  @spec heatmap(Client.t(), String.t(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, Error.t()}
  def heatmap(%Client{} = client, event_id, opts \\ []) do
    {dest, opts} = Keyword.pop(opts, :dest, :memory)
    API.download(client, "/api/events/#{event_id}/heatmap", dest, opts)
  end

  defp join_types(nil), do: nil
  defp join_types([]), do: nil
  defp join_types(types) when is_list(types), do: Enum.join(types, ",")
end
