defmodule UnifiClient.Protect.Time do
  @moduledoc """
  Time conversion for the Protect API.

  Protect expresses every timestamp as integer **milliseconds** since the
  Unix epoch. Functions in `UnifiClient.Protect.*` accept either a
  `DateTime.t()` or an integer already in that form; this module is the one
  place that normalises them.
  """

  @type t :: DateTime.t() | non_neg_integer()

  @doc """
  Converts a `DateTime` to epoch milliseconds; passes an integer through.

  ## Examples

      iex> UnifiClient.Protect.Time.to_ms(~U[2026-09-17 12:00:00Z])
      1789646400000

      iex> UnifiClient.Protect.Time.to_ms(1789646400000)
      1789646400000

  """
  @spec to_ms(t()) :: non_neg_integer()
  def to_ms(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)
  def to_ms(ms) when is_integer(ms) and ms >= 0, do: ms

  @doc """
  Like `to_ms/1` but passes `nil` through, for optional parameters.
  """
  @spec to_ms_or_nil(t() | nil) :: non_neg_integer() | nil
  def to_ms_or_nil(nil), do: nil
  def to_ms_or_nil(t), do: to_ms(t)
end
