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

  @type export_type :: :rotating | :timelapse

  @doc """
  Exports the recording of `camera_id` between `start` and `end_` to `dest`.

  ## Parameters

    * `start`, `end_` - `DateTime` or epoch ms; `end_` must be after `start`
    * `dest` - file path to write the MP4 to, or `:memory` for the bytes

  ## Options

    * `:type` - `:rotating` (default; the normal recording) or `:timelapse`
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
      {filename, opts} = Keyword.pop(opts, :filename, default_filename(dest))
      {timeout, opts} = Keyword.pop(opts, :timeout)

      path =
        API.with_query("/api/video/export",
          camera: camera_id,
          start: start_ms,
          end: end_ms,
          type: export_type(type),
          filename: filename
        )

      receive_timeout = timeout || export_timeout(client, start_ms, end_ms)

      API.download(client, path, dest, Keyword.put(opts, :receive_timeout, receive_timeout))
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

  defp export_type(:rotating), do: "rotating"
  defp export_type(:timelapse), do: "timelapse"

  defp default_filename(:memory), do: "export.mp4"
  defp default_filename(dest) when is_binary(dest), do: Path.basename(dest)
end
