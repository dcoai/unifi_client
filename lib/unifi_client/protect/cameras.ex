defmodule UnifiClient.Protect.Cameras do
  @moduledoc """
  Protect camera operations.

  Cameras are identified by their Protect `"id"` (a 24-hex string from
  `list/1` or `UnifiClient.Protect.bootstrap/1`), not by MAC.

  ## Example

      {:ok, cameras} = UnifiClient.Protect.Cameras.list(client)
      porch = Enum.find(cameras, &(&1["name"] == "Porch"))

      {:ok, jpeg} = UnifiClient.Protect.Cameras.snapshot(client, porch["id"], w: 640)
      {:ok, "porch.jpg"} = UnifiClient.Protect.Cameras.snapshot(client, porch["id"], dest: "porch.jpg")

  Every function takes a trailing `opts` keyword list that is passed to
  `Req.request/2` (e.g. `receive_timeout:`), after the keys it documents.
  """

  alias UnifiClient.{Client, Error}
  alias UnifiClient.Protect.{API, Time}

  @doc """
  Lists every camera the logged-in user can see.
  """
  @spec list(Client.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ []) do
    API.get(client, "/api/cameras", opts)
  end

  @doc """
  Fetches one camera by id.
  """
  @spec get(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, id, opts \\ []) do
    API.get(client, "/api/cameras/#{id}", opts)
  end

  @doc """
  Updates a camera's settings.

  `params` is sent as the PATCH body exactly as given — use the field names
  from `get/2` (e.g. `%{"name" => "Porch"}`, `%{"recordingSettings" =>
  %{"mode" => "always"}}`). Returns the updated camera.
  """
  @spec update(Client.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def update(%Client{} = client, id, params, opts \\ []) when is_map(params) do
    API.patch(client, "/api/cameras/#{id}", params, opts)
  end

  @doc """
  The stream channels of a camera map from `list/2` or `get/3`.

  Protect keeps up to three encodings per camera; each entry carries
  `"id"` (0 high, 1 medium, 2 low), `"width"`, `"height"`, `"fps"`,
  `"enabled"` and the RTSP fields. Pass the `"id"` as `channel:` to
  `UnifiClient.Protect.Video.export/6`. Pure; an empty list when absent.

      iex> UnifiClient.Protect.Cameras.channels(%{"channels" => [%{"id" => 0, "width" => 3840}]})
      [%{"id" => 0, "width" => 3840}]
      iex> UnifiClient.Protect.Cameras.channels(%{"id" => "c1"})
      []

  """
  @spec channels(map()) :: [map()]
  def channels(%{"channels" => channels}) when is_list(channels), do: channels
  def channels(camera) when is_map(camera), do: []

  @doc """
  Fetches a JPEG snapshot from a camera.

  ## Options

    * `:ts` - `DateTime` or epoch ms of the frame to fetch (default: live)
    * `:w`, `:h` - requested width / height in pixels
    * `:dest` - a file path to write the JPEG to, or `:memory` (default)
    * any other key is passed to `Req.request/2`

  ## Returns

    * `{:ok, jpeg}` - the image bytes, when `dest` is `:memory`
    * `{:ok, path}` - when `dest` is a path
    * `{:error, error}`

  """
  @spec snapshot(Client.t(), String.t(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, Error.t()}
  def snapshot(%Client{} = client, id, opts \\ []) do
    {ts, opts} = Keyword.pop(opts, :ts)
    {w, opts} = Keyword.pop(opts, :w)
    {h, opts} = Keyword.pop(opts, :h)
    {dest, opts} = Keyword.pop(opts, :dest, :memory)

    path = API.with_query("/api/cameras/#{id}/snapshot", ts: Time.to_ms_or_nil(ts), w: w, h: h)

    API.download(client, path, dest, opts)
  end
end
