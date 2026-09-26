defmodule UnifiClient.Protect.TimeTest do
  @moduledoc """
  Protect speaks epoch milliseconds. The conversion is small enough that its
  documentation is its test: `doctest` runs the examples in the module, so a
  doc that drifts from the code fails here rather than misleading a reader.
  """
  use ExUnit.Case, async: true

  doctest UnifiClient.Protect.Time
end
