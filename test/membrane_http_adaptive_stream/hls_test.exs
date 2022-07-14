defmodule Membrane.HTTPAdaptiveStream.HLSTest do
  use ExUnit.Case

  alias Membrane.HTTPAdaptiveStream.HLS

  describe "Deserialize manifest" do
    test "fails with empty content" do
      assert_raise ArgumentError, fn -> HLS.deserialize("", "") end
      assert_raise ArgumentError, fn -> HLS.deserialize("", "some invalid content") end
    end

    test "fails when name is not provided" do
      content = """
      #EXTM3U
      #EXT-X-VERSION:7
      #EXT-X-INDEPENDENT-SEGMENTS
      """

      assert_raise ArgumentError, fn -> HLS.deserialize("", content) end
      assert_raise ArgumentError, fn -> HLS.deserialize(1, content) end
    end

    test "stores name when content is valid" do
      content = """
      #EXTM3U
      #EXT-X-VERSION:7
      #EXT-X-INDEPENDENT-SEGMENTS
      """

      name = "index"

      manifest = HLS.deserialize(name, content)
      assert manifest.name == name
      assert manifest.tracks == %{}
    end

    test "parses manifest version" do
      version = 3

      content = """
      #EXTM3U
      #EXT-X-VERSION:#{version}
      #EXT-X-INDEPENDENT-SEGMENTS
      """

      manifest = HLS.deserialize("bar", content)
      assert manifest.version == version
    end

    test "adds the correct number of tracks" do
      content = """
      #EXTM3U
      #EXT-X-VERSION:7
      #EXT-X-INDEPENDENT-SEGMENTS
      #EXT-X-STREAM-INF:BANDWIDTH=1187651,CODECS="avc1.42e00a"
      muxed_video_480x270.m3u8
      #EXT-X-STREAM-INF:BANDWIDTH=609514,CODECS="avc1.42e00a"
      muxed_video_540x360.m3u8
      #EXT-X-STREAM-INF:BANDWIDTH=863865,CODECS="avc1.42e00a"
      muxed_video_720x480.m3u8
      """

      manifest = HLS.deserialize("foo", content)
      assert map_size(manifest.tracks) == 3
    end

    test "keeps track configuration information" do
      content = """
      #EXTM3U
      #EXT-X-VERSION:3
      #EXT-X-INDEPENDENT-SEGMENTS
      #EXT-X-STREAM-INF:BANDWIDTH=334400,AVERAGE-BANDWIDTH=325600,CODECS="avc1.42c01e,mp4a.40.2",RESOLUTION=416x234,FRAME-RATE=15.000
      stream_416x234.m3u8
      #EXT-X-STREAM-INF:BANDWIDTH=1020800,AVERAGE-BANDWIDTH=985600,CODECS="avc1.4d401e,mp4a.40.2",RESOLUTION=640x360,FRAME-RATE=15.000
      stream_640x360.m3u8
      #EXT-X-STREAM-INF:BANDWIDTH=1478400,AVERAGE-BANDWIDTH=1425600,CODECS="avc1.4d4029,mp4a.40.2",RESOLUTION=854x480,FRAME-RATE=30.000
      stream_854x480.m3u8
      """

      manifest = HLS.deserialize("foo", content)

      [
        %{
          track_name: "stream_416x234",
          bandwidth: 334_400,
          codecs: ["avc1.42c01e", "mp4a.40.2"],
          resolution: [416, 234],
          frame_rate: 15.0
        }
      ]
      |> Enum.each(fn config ->
        track_config = Map.get(manifest.tracks, config.track_name)

        Enum.each(config, fn {key, want} ->
          assert Map.get(track_config, key) == want
        end)
      end)
    end
  end
end
