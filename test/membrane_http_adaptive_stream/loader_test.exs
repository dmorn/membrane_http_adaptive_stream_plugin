defmodule Membrane.HTTPAdaptiveStream.LoaderTest do
  use ExUnit.Case

  alias Membrane.HTTPAdaptiveStream.Loader.FS
  alias Membrane.HTTPAdaptiveStream.Loader
  alias Membrane.HTTPAdaptiveStream.HLS

  @manifest_base_path "./test/membrane_http_adaptive_stream/integration_test/fixtures/audio_multiple_video_tracks/"
  @manifest_index_path Path.join([@manifest_base_path, "index.m3u8"])

  describe "Load playlist from disk" do
    test "fails when manifest location is invalid" do
      loader = Loader.new(%FS{base_path: @manifest_base_path}, HLS)
      assert {:error, _reason} = Loader.load_manifest(loader, "invalid location")
    end
  end
end
