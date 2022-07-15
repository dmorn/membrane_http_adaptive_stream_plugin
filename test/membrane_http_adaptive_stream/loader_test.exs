defmodule Membrane.HTTPAdaptiveStream.LoaderTest do
  use ExUnit.Case

  alias Membrane.HTTPAdaptiveStream.Loader.FS
  alias Membrane.HTTPAdaptiveStream.Loader
  alias Membrane.HTTPAdaptiveStream.HLS
  alias Membrane.HTTPAdaptiveStream.Manifest

  @manifest_base_path "./test/membrane_http_adaptive_stream/integration_test/fixtures/audio_multiple_video_tracks/"

  describe "Load playlist from disk" do
    test "fails when manifest location is invalid" do
      loader = Loader.new(%FS{base_path: @manifest_base_path}, HLS)
      assert {:error, _reason} = Loader.load_manifest(loader, "invalid location")
    end

    test "loads a valid manifest" do
      loader = Loader.new(%FS{base_path: @manifest_base_path}, HLS)
      assert {:ok, %Manifest{}} = Loader.load_manifest(loader, "index.m3u8")
    end

    test "loads media tracks" do
      loader = Loader.new(%FS{base_path: @manifest_base_path}, HLS)
      {:ok, manifest} = Loader.load_manifest(loader, "index.m3u8")

      Enum.each(manifest.track_configs, fn {_track_id, config} ->
        assert {:ok, %Manifest.Track{}} = Loader.load_track(loader, config)
      end)
    end

    test "loads segments" do
      loader = Loader.new(%FS{base_path: @manifest_base_path}, HLS)
      {:ok, manifest} = Loader.load_manifest(loader, "index.m3u8")

      Enum.each(manifest.track_configs, fn {_track_id, config} ->
        {:ok, track} = Loader.load_track(loader, config)

        Enum.each(track.segments, fn segment ->
          assert {:ok, _data} = Loader.load_segment(loader, segment)
        end)
      end)
    end
  end
end
