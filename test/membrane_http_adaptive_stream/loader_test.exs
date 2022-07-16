defmodule Membrane.HTTPAdaptiveStream.LoaderTest do
  use ExUnit.Case

  alias Membrane.HTTPAdaptiveStream.Loader.FS
  alias Membrane.HTTPAdaptiveStream.Loader
  alias Membrane.HTTPAdaptiveStream.HLS
  alias Membrane.HTTPAdaptiveStream.Manifest

  @manifest_index_path "./test/membrane_http_adaptive_stream/integration_test/fixtures/audio_multiple_video_tracks/index.m3u8"
  @loader Loader.new(%FS{location: @manifest_index_path}, HLS)

  describe "Load playlist from disk" do
    test "fails when manifest location is invalid" do
      loader = Loader.new(%FS{location: "invalid location"}, HLS)
      assert {:error, _reason} = Loader.load_manifest(loader)
    end

    test "loads a valid manifest" do
      assert {:ok, %Manifest{}} = Loader.load_manifest(@loader)
    end

    test "loads media tracks" do
      {:ok, manifest} = Loader.load_manifest(@loader)

      Enum.each(manifest.track_configs, fn {_track_id, config} ->
        assert {:ok, %Manifest.Track{}} = Loader.load_track(@loader, config)
      end)
    end

    test "loads segments" do
      {:ok, manifest} = Loader.load_manifest(@loader)

      Enum.each(manifest.track_configs, fn {_track_id, config} ->
        {:ok, track} = Loader.load_track(@loader, config)

        Enum.each(track.segments, fn segment ->
          assert {:ok, _data} = Loader.load_segment(@loader, segment)
        end)
      end)
    end
  end
end
