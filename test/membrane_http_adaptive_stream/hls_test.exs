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
      assert manifest.track_configs == %{}
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
      assert map_size(manifest.track_configs) == 3
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
        # TODO: check other tracks as well
        %{
          track_name: "stream_416x234",
          bandwidth: 334_400,
          codecs: ["avc1.42c01e", "mp4a.40.2"],
          resolution: [416, 234],
          frame_rate: 15.0
        }
      ]
      |> Enum.each(fn config ->
        track_config = Map.get(manifest.track_configs, config.track_name)

        Enum.each(config, fn {key, want} ->
          assert Map.get(track_config, key) == want
        end)
      end)
    end

    test "preserves path query parameters if present" do
      # NOTE: this is a technique used by some services to forward
      # authentication information from master playlists to final segments.
      # Event though it is not a standard, it works pretty well in practice.
      content = """
      #EXTM3U
      #EXT-X-VERSION:3
      #EXT-X-INDEPENDENT-SEGMENTS
      #EXT-X-STREAM-INF:BANDWIDTH=1020588,AVERAGE-BANDWIDTH=985600,CODECS="avc1.77.30,mp4a.40.2",RESOLUTION=640x360,FRAME-RATE=29.970,AUDIO="PROGRAM_AUDIO"
      stream_with_token.m3u8?t=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2NTc5MTYzMDcsImlhdCI6MTY1Nzg3MzEwNywiaXNzIjoiY2RwIiwia2VlcF9zZWdtZW50cyI6bnVsbCwia2luZCI6ImNoaWxkIiwicGFyZW50IjoiNmhReUhyUGRhRTNuL3N0cmVhbS5tM3U4Iiwic3ViIjoiNmhReUhyUGRhRTNuL3N0cmVhbV82NDB4MzYwXzgwMGsubTN1OCIsInRyaW1fZnJvbSI6NTIxLCJ0cmltX3RvIjpudWxsLCJ1c2VyX2lkIjoiMzA2IiwidXVpZCI6bnVsbCwidmlzaXRvcl9pZCI6ImI0NGFlZjYyLTA0MTYtMTFlZC04NTRmLTBhNThhOWZlYWMwMiJ9.eVrBzEBbjHxDcg6xnZXfXy0ZoNoj_seaZwaja_WDwuc
      """

      manifest = HLS.deserialize_master_manifest("foo", content)
      track_config = Map.get(manifest.track_configs, "stream_with_token")

      assert track_config.query ==
               "t=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2NTc5MTYzMDcsImlhdCI6MTY1Nzg3MzEwNywiaXNzIjoiY2RwIiwia2VlcF9zZWdtZW50cyI6bnVsbCwia2luZCI6ImNoaWxkIiwicGFyZW50IjoiNmhReUhyUGRhRTNuL3N0cmVhbS5tM3U4Iiwic3ViIjoiNmhReUhyUGRhRTNuL3N0cmVhbV82NDB4MzYwXzgwMGsubTN1OCIsInRyaW1fZnJvbSI6NTIxLCJ0cmltX3RvIjpudWxsLCJ1c2VyX2lkIjoiMzA2IiwidXVpZCI6bnVsbCwidmlzaXRvcl9pZCI6ImI0NGFlZjYyLTA0MTYtMTFlZC04NTRmLTBhNThhOWZlYWMwMiJ9.eVrBzEBbjHxDcg6xnZXfXy0ZoNoj_seaZwaja_WDwuc"
    end

    test "deserializes subtitle tracks" do
      content = """
      #EXTM3U
      #EXT-X-VERSION:3
      #EXT-X-INDEPENDENT-SEGMENTS
      #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles",NAME="German (Germany)",DEFAULT=NO,AUTOSELECT=NO,FORCED=NO,LANGUAGE="de-DE",URI="subtitles.m3u8?t=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2NTc5MTY0MjYsImlhdCI6MTY1Nzg3MzIyNiwiaXNzIjoiY2RwIiwia2VlcF9zZWdtZW50cyI6bnVsbCwia2luZCI6ImNoaWxkIiwicGFyZW50IjoiNmhReUhyUGRhRTNuL3N0cmVhbS5tM3U4Iiwic3ViIjoiNmhReUhyUGRhRTNuL3N1YnRpdGxlcy5tM3U4IiwidHJpbV9mcm9tIjo1MjEsInRyaW1fdG8iOm51bGwsInVzZXJfaWQiOiIzMDYiLCJ1dWlkIjpudWxsLCJ2aXNpdG9yX2lkIjoiZmI0NDRlYjgtMDQxNi0xMWVkLTgxODAtMGE1OGE5ZmVhYzAyIn0.hZBdfremVP_T7XRcVLz-vmDfgyP_sXZhyK_liv4ekho"
      """

      manifest = HLS.deserialize_master_manifest("foo", content)
      track_config = Map.get(manifest.track_configs, "subtitles")

      assert track_config
      assert track_config.language == "de-DE"
      assert track_config.track_name == "subtitles"

      assert track_config.query ==
               "t=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2NTc5MTY0MjYsImlhdCI6MTY1Nzg3MzIyNiwiaXNzIjoiY2RwIiwia2VlcF9zZWdtZW50cyI6bnVsbCwia2luZCI6ImNoaWxkIiwicGFyZW50IjoiNmhReUhyUGRhRTNuL3N0cmVhbS5tM3U4Iiwic3ViIjoiNmhReUhyUGRhRTNuL3N1YnRpdGxlcy5tM3U4IiwidHJpbV9mcm9tIjo1MjEsInRyaW1fdG8iOm51bGwsInVzZXJfaWQiOiIzMDYiLCJ1dWlkIjpudWxsLCJ2aXNpdG9yX2lkIjoiZmI0NDRlYjgtMDQxNi0xMWVkLTgxODAtMGE1OGE5ZmVhYzAyIn0.hZBdfremVP_T7XRcVLz-vmDfgyP_sXZhyK_liv4ekho"
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

    test "detects when track is finished" do
      # TODO: what about when track event type is VOD? In that case it should
      # be marked as finished as well.

      track = Track.new(%Track.Config{id: "foo", track_name: "bar"})

      content = """
      #EXTM3U
      #EXT-X-VERSION:7
      #EXT-X-TARGETDURATION:10
      #EXT-X-MEDIA-SEQUENCE:0
      #EXT-X-DISCONTINUITY-SEQUENCE:0
      #EXT-X-MAP:URI="video_header_video_track_part0_.mp4"
      #EXTINF:10.0,
      video_segment_0_video_track.m4s
      #EXTINF:2.0,
      video_segment_1_video_track.m4s
      #EXT-X-ENDLIST
      """

      track = HLS.deserialize_media_track(track, content)
      assert track.finished?
    end

    test "stores segment_extension" do
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
      """

      track = HLS.deserialize_media_track(track, content)
      assert track.segment_extension == ".m4s"
    end

    test "stores query if present" do
      content = """
      #EXTM3U
      #EXT-X-VERSION:3
      #EXT-X-TARGETDURATION:7
      #EXT-X-MEDIA-SEQUENCE:1
      #EXT-X-PLAYLIST-TYPE:VOD
      #EXT-X-PROGRAM-DATE-TIME:2020-09-10T06:08:25.701Z
      #EXTINF:6.00600,
      a/stream_1280x720_3300k/00000/stream_1280x720_3300k_00522.ts?t=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2NTc5MTYzMDEsImlhdCI6MTY1Nzg3MzEwMSwiaXNzIjoiY2RwIiwic3ViIjoiNmhReUhyUGRhRTNuL2Evc3RyZWFtXzEyODB4NzIwXzMzMDBrIiwidXNlcl9pZCI6IjMwNiIsInZpc2l0b3JfaWQiOiJiMGMyMGVkZS0wNDE2LTExZWQtYTYyMS0wYTU4YTlmZWFjMDIifQ.Fj7CADyZeoWtpaqiZLPodNHMWhlGeKjxLwpMR7lygqk
      """

      track = Track.new(%Track.Config{id: "foo", track_name: "bar"})

      track = HLS.deserialize_media_track(track, content)
      segment = Qex.last!(track.segments)

      assert segment.name == "a/stream_1280x720_3300k/00000/stream_1280x720_3300k_00522"

      assert segment.query ==
               "t=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE2NTc5MTYzMDEsImlhdCI6MTY1Nzg3MzEwMSwiaXNzIjoiY2RwIiwic3ViIjoiNmhReUhyUGRhRTNuL2Evc3RyZWFtXzEyODB4NzIwXzMzMDBrIiwidXNlcl9pZCI6IjMwNiIsInZpc2l0b3JfaWQiOiJiMGMyMGVkZS0wNDE2LTExZWQtYTYyMS0wYTU4YTlmZWFjMDIifQ.Fj7CADyZeoWtpaqiZLPodNHMWhlGeKjxLwpMR7lygqk"
    end
  end
end
