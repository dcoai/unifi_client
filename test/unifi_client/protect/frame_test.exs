defmodule UnifiClient.Protect.FrameTest do
  use ExUnit.Case, async: true

  # Corrupt-deflate fixtures crash the throwaway inflate process by design;
  # its emulator crash report is the loud signal, not noise, but not in the test log.
  @moduletag :capture_log

  alias UnifiClient.Protect.Frame

  # Builds one packet. `type`/`format` are the wire numbers.
  defp packet(type, format, deflated?, payload) do
    bytes = if deflated?, do: :zlib.compress(payload), else: payload

    <<type::8, format::8, if(deflated?, do: 1, else: 0)::8, 0::8, byte_size(bytes)::32-big,
      bytes::binary>>
  end

  defp action(map, deflated? \\ false), do: packet(1, 1, deflated?, Jason.encode!(map))
  defp payload(term, deflated? \\ false), do: packet(2, 1, deflated?, Jason.encode!(term))

  @action %{"action" => "update", "modelKey" => "camera", "id" => "c1", "newUpdateId" => "u2"}
  @data %{"isMotionDetected" => true}

  describe "decode/1" do
    test "JSON action, plain" do
      assert {:ok, %Frame{type: :action, format: :json, payload: @action}, ""} =
               Frame.decode(action(@action))
    end

    test "JSON payload, deflated" do
      assert {:ok, %Frame{type: :payload, format: :json, payload: @data}, ""} =
               Frame.decode(payload(@data, true))
    end

    test "UTF-8 and buffer formats return the bytes" do
      assert {:ok, %Frame{format: :utf8, payload: "héllo"}, ""} =
               Frame.decode(packet(2, 2, false, "héllo"))

      assert {:ok, %Frame{format: :buffer, payload: <<0, 1, 2>>}, ""} =
               Frame.decode(packet(2, 3, true, <<0, 1, 2>>))
    end

    test "trailing bytes are returned as rest" do
      assert {:ok, %Frame{}, "tail"} = Frame.decode(action(@action) <> "tail")
    end

    test "unknown type and format numbers are surfaced, not rejected" do
      assert {:ok, %Frame{type: {:unknown, 9}, format: {:unknown, 7}, payload: "x"}, ""} =
               Frame.decode(packet(9, 7, false, "x"))
    end

    test "a short header is incomplete" do
      assert {:error, :incomplete_header} = Frame.decode("")
      assert {:error, :incomplete_header} = Frame.decode(<<1, 1, 0, 0, 0, 0, 0>>)
    end

    test "a short payload is incomplete with the sizes" do
      full = action(@action)
      cut = binary_part(full, 0, byte_size(full) - 3)
      needed = byte_size(full) - 8
      assert {:error, {:incomplete_payload, ^needed, have}} = Frame.decode(cut)
      assert have == needed - 3
    end

    test "invalid JSON is an error" do
      assert {:error, {:invalid_json, _}} = Frame.decode(packet(1, 1, false, "{not json"))
    end

    test "corrupt deflate data is an error, not a crash" do
      assert {:error, :bad_deflate} = Frame.decode(packet(2, 3, true, "") |> corrupt_deflate())
      # deflated flag set on data that is not zlib at all
      assert {:error, :bad_deflate} = Frame.decode(<<2, 3, 1, 0, 4::32-big, "abcd">>)
    end

    test "never raises on random input" do
      for _ <- 1..200 do
        len = :rand.uniform(64) - 1
        bin = :crypto.strong_rand_bytes(len)
        assert match?({:ok, _, _}, Frame.decode(bin)) or match?({:error, _}, Frame.decode(bin))
      end
    end

    test "never raises on random input with a plausible header" do
      for _ <- 1..200 do
        body = :crypto.strong_rand_bytes(:rand.uniform(32))
        deflated = :rand.uniform(2) - 1

        bin =
          <<:rand.uniform(3)::8, :rand.uniform(3)::8, deflated::8, 0::8, byte_size(body)::32-big,
            body::binary>>

        assert match?({:ok, _, _}, Frame.decode(bin)) or match?({:error, _}, Frame.decode(bin))
      end
    end
  end

  describe "decode_message/1" do
    test "pairs an action with its payload" do
      bin = action(@action, true) <> payload(@data) <> "rest"
      assert {:ok, %{action: @action, data: @data}, "rest"} = Frame.decode_message(bin)
    end

    test "payload before action is an unexpected sequence" do
      assert {:error, {:unexpected_sequence, %{got: {:payload, :json}, want: {:action, :json}}}} =
               Frame.decode_message(payload(@data) <> action(@action))
    end

    test "two actions in a row is an unexpected sequence" do
      assert {:error, {:unexpected_sequence, %{got: {:action, :json}, want: {:payload, nil}}}} =
               Frame.decode_message(action(@action) <> action(@action))
    end

    test "an action with a non-JSON format is rejected" do
      assert {:error, {:unexpected_sequence, _}} =
               Frame.decode_message(packet(1, 2, false, "text") <> payload(@data))
    end

    test "only the action present is incomplete, so a stream can wait" do
      assert {:error, :incomplete_header} = Frame.decode_message(action(@action))
      half = payload(@data) |> binary_part(0, 10)
      assert {:error, {:incomplete_payload, _, _}} = Frame.decode_message(action(@action) <> half)
    end
  end

  # Flip bytes inside the zlib stream so the header is plausible but the body is not.
  defp corrupt_deflate(<<hdr::binary-size(8), z0, z1, rest::binary>>) do
    body = :binary.copy(<<0xFF>>, byte_size(rest))
    <<hdr::binary, z0, z1, body::binary>>
  end
end
