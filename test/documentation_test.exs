defmodule UnifiClient.DocumentationTest do
  @moduledoc """
  The documentation is part of the library, so it is tested like the rest of
  it.

  Two properties, both about what a reader meets: every function this
  library offers says what it does, and every example it shows is one that
  runs. The second is `doctest` in the module tests; the first is here,
  because a `@doc` that was never written is invisible in review — nothing
  fails, the function simply appears in the docs with nothing under it.
  """
  use ExUnit.Case, async: true

  # Functions the compiler writes, which no one documents: struct builders,
  # the supervisor's child spec, and the callbacks of whatever behaviours a
  # module implements. The behaviours are read from the module itself rather
  # than listed here, so adding one does not need a change to this test.
  @generated [{:__struct__, 0}, {:__struct__, 1}, {:child_spec, 1}, {:child_spec, 2}]

  test "every public function is documented, or deliberately hidden" do
    undocumented =
      for module <- modules(),
          # A module marked `@moduledoc false` is internal whole: ExDoc shows
          # none of it, and asking each of its functions to repeat the marker
          # would be ceremony rather than information.
          not hidden?(module),
          {{kind, name, arity}, _line, _sig, doc, _meta} <- docs(module),
          kind in [:function, :macro],
          doc == :none,
          {name, arity} not in @generated,
          {name, arity} not in callbacks(module),
          do: "#{inspect(module)}.#{name}/#{arity}"

    assert undocumented == [],
           "these are public and say nothing. Write a @doc, or @doc false if " <>
             "they are internal:\n  " <> Enum.join(undocumented, "\n  ")
  end

  test "every module says what it is for" do
    silent =
      for module <- modules(),
          {:docs_v1, _, _, _, moduledoc, _, _} = Code.fetch_docs(module),
          # `:none` is an oversight; `:hidden` is `@moduledoc false`, said
          # on purpose.
          moduledoc == :none,
          do: inspect(module)

    assert silent == [],
           "these modules have no @moduledoc (use @moduledoc false for an " <>
             "internal one):\n  " <> Enum.join(silent, "\n  ")
  end

  defp hidden?(module) do
    {:docs_v1, _, _, _, moduledoc, _, _} = Code.fetch_docs(module)
    moduledoc == :hidden
  end

  defp modules do
    {:ok, modules} = :application.get_key(:unifi_client, :modules)
    Enum.sort(modules)
  end

  defp docs(module) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)
    docs
  end

  # Every callback of every behaviour the module implements, as {name, arity}.
  defp callbacks(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.flat_map(fn behaviour ->
      if function_exported?(behaviour, :behaviour_info, 1),
        do: behaviour.behaviour_info(:callbacks),
        else: []
    end)
  end
end
