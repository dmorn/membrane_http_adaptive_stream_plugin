defmodule Membrane.HTTPAdaptiveStream.HLSTest do
  use ExUnit.Case

  alias Membrane.HTTPAdaptiveStream.HLS
  alias Membrane.HTTPAdaptiveStream.Manifest.Track

  describe "Deserialize master manifest" do
    test "fails with empty content" do
      assert_raise ArgumentError, fn -> HLS.deserialize_master_manifest("", "") end

      assert_raise ArgumentError, fn ->
        HLS.deserialize_master_manifest("", "some invalid content")
      end
    end

    test "fails when name is not provided" do
      content = """
      #EXTM3U
      #EXT-X-VERSION:7
      #EXT-X-INDEPENDENT-SEGMENTS
      """

      assert_raise ArgumentError, fn -> HLS.deserialize_master_manifest("", content) end
      assert_raise ArgumentError, fn -> HLS.deserialize_master_manifest(1, content) end
    end

    test "stores name when content is valid" do
      content = """
      #EXTM3U
      #EXT-X-VERSION:7
      #EXT-X-INDEPENDENT-SEGMENTS
      """

      name = "index"

      manifest = HLS.deserialize_master_manifest(name, content)
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

      manifest = HLS.deserialize_master_manifest("bar", content)
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

      manifest = HLS.deserialize_master_manifest("foo", content)
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

      manifest = HLS.deserialize_master_manifest("foo", content)

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

  describe "Deserialize media track" do
    test "fails with empty content" do
      track = Track.new(%Track.Config{id: "foo", track_name: "bar"})

      assert_raise ArgumentError, fn -> HLS.deserialize_media_track(track, "") end

      assert_raise ArgumentError, fn ->
        HLS.deserialize_media_track(track, "some invalid content")
      end
    end

    test "fails when track is not provided" do
      content = """
      #EXTM3U
      #EXT-X-VERSION:7
      #EXT-X-TARGETDURATION:3
      #EXT-X-MEDIA-SEQUENCE:0
      #EXT-X-DISCONTINUITY-SEQUENCE:0
      """

      assert_raise ArgumentError, fn -> HLS.deserialize_media_track(nil, content) end
    end

    test "collects manifest header" do
      version = 4
      duration = 3
      sequence = 1
      discontinuity = 1
      track = Track.new(%Track.Config{id: "foo", track_name: "bar"})

      content = """
      #EXTM3U
      #EXT-X-VERSION:#{version}
      #EXT-X-TARGETDURATION:#{duration}
      #EXT-X-MEDIA-SEQUENCE:#{sequence}
      #EXT-X-DISCONTINUITY-SEQUENCE:#{discontinuity}
      """

      track = HLS.deserialize_media_track(track, content)
      assert track.version == version
      assert track.target_segment_duration == duration
      assert track.current_seq_num == sequence
      assert track.current_discontinuity_seq_num == discontinuity
    end

    test "collects segments" do
      track = Track.new(%Track.Config{id: "foo", track_name: "bar"})

      content = """
      #EXTM3U
      #EXT-X-VERSION:7
      #EXT-X-TARGETDURATION:3
      #EXT-X-MEDIA-SEQUENCE:0
      #EXT-X-DISCONTINUITY-SEQUENCE:0
      #EXT-X-MAP:URI="audio_header_audio_track_part0_.mp4"
      #EXTINF:2.020136054,
      audio_segment_0_audio_track.m4s
      #EXTINF:2.020136054,
      audio_segment_1_audio_track.m4s
      #EXTINF:2.020136054,
      audio_segment_2_audio_track.m4s
      #EXTINF:2.020136054,
      audio_segment_3_audio_track.m4s
      #EXTINF:1.95047619,
      audio_segment_4_audio_track.m4s
      """

      track = HLS.deserialize_media_track(track, content)
      assert Enum.count(track.segments) == 5
    end
  end
end
