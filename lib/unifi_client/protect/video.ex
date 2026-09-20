defmodule UnifiClient.Protect.Video do
  @moduledoc """
  Recorded video export from Protect.

  `export/6` asks the console to render the footage between two instants
  for one camera as an MP4 and streams it to disk. The console transcodes
  on demand, so a request takes roughly as long as the clip is long; see
  `export_timeout/4` for how the wait is sized.

  ## Example

      start = ~U[2026-09-17 08:00:00Z]
      finish = DateTime.add(start, 60, :second)

      {:ok, "porch.mp4"} =
        UnifiClient.Protect.Video.export(client, porch["id"], start, finish, "porch.mp4")

  """

  alias UnifiClient.{Client, Error}
  alias UnifiClient.Protect.{API, Time}

  # How many seconds of wall-clock to allow per second of footage. A UNVR
  # exports a rotating clip at better than real time; 2× leaves headroom for
  # a busy console or a slow link without turning a genuine hang into a
  # ten-minute wait. Callers that know better pass `timeout:`.
  @seconds_per_clip_second 2

  # Concurrent exports per `export_many/6`. The NVR's export capacity is a
  # property of the console we cannot measure from here; two keeps a UNVR
  # responsive while still halving a six-camera batch. Callers who have
  # measured their console pass `max_concurrency:`.
  @default_max_concurrency 2

  @type export_type :: :rotating | :timelapse
  @type camera_result :: {String.t(), {:ok, Path.t() | binary()} | {:error, Error.t()}}

  @doc """
  Exports the recording of `camera_id` between `start` and `end_` to `dest`.

  ## Parameters

    * `start`, `end_` - `DateTime` or epoch ms; `end_` must be after `start`
    * `dest` - file path to write the MP4 to, or `:memory` for the bytes

  ## Options

    * `:type` - `:rotating` (default; the normal recording) or `:timelapse`
    * `:channel` - stream to export: `0` high (default on the console), `1`
      medium, `2` low. See `UnifiClient.Protect.Cameras.channels/1`.
    * `:fps` - frames per second for a `:timelapse` export
    * `:filename` - the `filename` query parameter; defaults to the basename
      of `dest` (or `"export.mp4"` for `:memory`)
    * `:timeout` - overrides the derived request timeout, in ms
    * any other key is passed to `Req.request/2`

  ## Returns

    * `{:ok, dest}` - the MP4 was written
    * `{:ok, binary}` - when `dest` is `:memory`
    * `{:error, %Error{code: :timeout}}` - the console did not finish within
      the timeout; no file is left behind
    * `{:error, error}` - no footage for the window, bad camera, etc.; no
      file is written

  """
  @spec export(Client.t(), String.t(), Time.t(), Time.t(), Path.t() | :memory, keyword()) ::
          {:ok, Path.t() | binary()} | {:error, Error.t()}
  def export(%Client{} = client, camera_id, start, end_, dest, opts \\ []) do
    start_ms = Time.to_ms(start)
    end_ms = Time.to_ms(end_)

    if end_ms <= start_ms do
      {:error, Error.new("Export window is empty: end must be after start", :invalid_window)}
    else
      {type, opts} = Keyword.pop(opts, :type, :rotating)
      {channel, opts} = Keyword.pop(opts, :channel)
      {fps, opts} = Keyword.pop(opts, :fps)
      {filename, opts} = Keyword.pop(opts, :filename, default_filename(dest))
      {timeout, opts} = Keyword.pop(opts, :timeout)

      path =
        API.with_query("/api/video/export",
          camera: camera_id,
          channel: channel,
          start: start_ms,
          end: end_ms,
          type: export_type(type),
          fps: fps,
          filename: filename
        )

      receive_timeout = timeout || export_timeout(client, start_ms, end_ms)

      API.download(client, path, dest, Keyword.put(opts, :receive_timeout, receive_timeout))
    end
  end

  @doc """
  Exports the same window from several cameras concurrently.

  One file per camera, `<dir>/<camera_id>.mp4` by default. Each export is
  `export/6` with the same `start`/`end_` and `opts`, run in tasks
  **linked to the caller**: killing the calling process kills every
  in-flight download, which is how a job is cancelled. `dir` is created if
  missing.

  ## Options

    * `:max_concurrency` - exports in flight at once (default
      `#{@default_max_concurrency}`; see the module source for why)
    * `:dest` - `camera_id -> path` function overriding the file layout
    * every other key is passed to `export/6` (`:channel`, `:type`, `:timeout`, …)

  ## Returns

    * `{:ok, [{camera_id, {:ok, path} | {:error, error}}]}` - one entry per
      camera, in the order given; a camera with no footage is an error entry,
      not a batch failure
    * `{:error, error}` - nothing was attempted: `:app_unavailable`,
      `:invalid_window`, or `:dir_error` (`reason` holds the posix error)

  """
  @spec export_many(Client.t(), [String.t()], Time.t(), Time.t(), Path.t(), keyword()) ::
          {:ok, [camera_result()]} | {:error, Error.t()}
  def export_many(%Client{} = client, camera_ids, start, end_, dir, opts \\ [])
      when is_list(camera_ids) and is_binary(dir) do
    {max_concurrency, opts} = Keyword.pop(opts, :max_concurrency, @default_max_concurrency)
    {dest, opts} = Keyword.pop(opts, :dest, &Path.join(dir, "#{&1}.mp4"))

    with :ok <- check_app(client),
         :ok <- check_window(start, end_),
         :ok <- ensure_dir(dir) do
      results =
        camera_ids
        |> Task.async_stream(
          fn id -> {id, export(client, id, start, end_, dest.(id), opts)} end,
          max_concurrency: max_concurrency,
          ordered: true,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, result} -> result end)

      {:ok, results}
    end
  end

  @doc """
  The request timeout `export/6` uses for a clip, in milliseconds.

  Derived from the clip length — `#{@seconds_per_clip_second}` s of waiting
  per second of footage — but never below the client's own `timeout`, so a
  short clip still gets the normal request budget. An explicit `timeout:`
  in `opts` wins outright.

  ## Examples

      iex> {:ok, client} = UnifiClient.Client.new(host: "h", timeout: 30_000)
      iex> UnifiClient.Protect.Video.export_timeout(client, 0, 10_000)
      30000
      iex> UnifiClient.Protect.Video.export_timeout(client, 0, 60_000)
      120000
      iex> UnifiClient.Protect.Video.export_timeout(client, 0, 60_000, timeout: 5_000)
      5000

  """
  @spec export_timeout(Client.t(), Time.t(), Time.t(), keyword()) :: pos_integer()
  def export_timeout(%Client{timeout: client_timeout}, start, end_, opts \\ []) do
    case Keyword.fetch(opts, :timeout) do
      {:ok, timeout} when is_integer(timeout) and timeout > 0 ->
        timeout

      :error ->
        clip_ms = Time.to_ms(end_) - Time.to_ms(start)
        max(client_timeout, clip_ms * @seconds_per_clip_second)
    end
  end

  defp check_app(client) do
    if Client.app_available?(client, :protect),
      do: :ok,
      else: {:error, Error.app_unavailable(:protect)}
  end

  defp check_window(start, end_) do
    if Time.to_ms(end_) <= Time.to_ms(start),
      do: {:error, Error.new("Export window is empty: end must be after start", :invalid_window)},
      else: :ok
  end

  defp ensure_dir(dir) do
    case File.mkdir_p(dir) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, Error.new("Cannot create #{dir}: #{reason}", :dir_error, reason)}
    end
  end

  defp export_type(:rotating), do: "rotating"
  defp export_type(:timelapse), do: "timelapse"

  defp default_filename(:memory), do: "export.mp4"
  defp default_filename(dest) when is_binary(dest), do: Path.basename(dest)
end
