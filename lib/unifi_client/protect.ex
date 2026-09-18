defmodule UnifiClient.Protect do
  @moduledoc """
  UniFi Protect — the video application on UniFi OS consoles.

  Protect shares the console login with Network, so the same authenticated
  `UnifiClient.Client` is used; only `type: :udm_pro` clients have it (a
  self-hosted `:controller` returns `{:error, %Error{code: :app_unavailable}}`
  from every function here).

  ## Example

      {:ok, client} = UnifiClient.Client.new(host: "unvr.local", username: "admin", password: "secret")
      {:ok, client} = UnifiClient.Auth.login(client)

      {:ok, boot} = UnifiClient.Protect.bootstrap(client)
      {:ok, cameras} = UnifiClient.Protect.Cameras.list(client)
      {:ok, jpeg} = UnifiClient.Protect.Cameras.snapshot(client, hd(cameras)["id"])

  ## Modules

  - `UnifiClient.Protect.Cameras` — list, inspect, update, snapshot
  - `UnifiClient.Protect.Events` — motion / smart-detect / ring events, thumbnails, heatmaps
  - `UnifiClient.Protect.Video` — export recorded footage to MP4
  - `UnifiClient.Protect.WebSocket` — live updates (motion, state changes) with resume
  - `UnifiClient.Protect.Time` — `DateTime` ⇄ epoch-millisecond conversion

  Responses are the console's raw JSON as maps with string keys; see
  `spec.md` §6 for the surface and its status.
  """

  alias UnifiClient.{Client, Error}
  alias UnifiClient.Protect.API

  @doc """
  Fetches the bootstrap document: the NVR, every camera, user, live view
  and the `lastUpdateId` a WebSocket subscription resumes from.

  This is one large response; prefer the resource modules for routine
  reads.

  `opts` are passed to `Req.request/2` (e.g. `receive_timeout:`).

  ## Returns

    * `{:ok, map}` - keys include `"nvr"`, `"cameras"`, `"users"`, `"lastUpdateId"`
    * `{:error, error}`

  """
  @spec bootstrap(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def bootstrap(%Client{} = client, opts \\ []) do
    API.get(client, "/api/bootstrap", opts)
  end

  @doc """
  Fetches the NVR record (console model, version, storage, recording
  settings).
  """
  @spec nvr(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def nvr(%Client{} = client, opts \\ []) do
    API.get(client, "/api/nvr", opts)
  end
end
