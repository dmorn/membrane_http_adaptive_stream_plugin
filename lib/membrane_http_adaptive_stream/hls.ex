defmodule Membrane.HTTPAdaptiveStream.HLS do
  @moduledoc """
  `Membrane.HTTPAdaptiveStream.Manifest` implementation for HTTP Live Streaming.

  Currently supports up to one audio and video stream.
  """
  use Ratio

  @behaviour Membrane.HTTPAdaptiveStream.Manifest

  alias Membrane.HTTPAdaptiveStream.Manifest
  alias Membrane.HTTPAdaptiveStream.Manifest.Track
  alias Membrane.Time

  @version 7

  @master_playlist_header"""
  #EXTM3U
  #EXT-X-VERSION:#{@version}
  #EXT-X-INDEPENDENT-SEGMENTS
  """

  defmodule SegmentAttribute do
    @moduledoc """
    Implementation of `Membrane.HTTPAdaptiveStream.Manifest.SegmentAttribute` behaviour for HTTP Live Streaming
    """
    @behaviour Membrane.HTTPAdaptiveStream.Manifest.SegmentAttribute

    import Membrane.HTTPAdaptiveStream.Manifest.SegmentAttribute

    @impl true
    def serialize(discontinuity(header_name, number)) do
      [
        "#EXT-X-DISCONTINUITY-SEQUENCE:#{number}",
        "#EXT-X-DISCONTINUITY",
        "#EXT-X-MAP:URI=#{header_name}"
      ]
    end
  end

  @doc """
  Generates EXTM3U playlist for the given manifest
  """
  @impl true
  def serialize(%Manifest{} = manifest) do
    tracks_by_content = manifest.tracks |> Map.values() |> Enum.group_by(& &1.content_type)
    main_manifest_name = "#{manifest.name}.m3u8"

    case {tracks_by_content[:audio], tracks_by_content[:video]} do
      {[audio], nil} ->
        [{main_manifest_name, build_master_playlist([audio], nil)}, {"audio.m3u8", serialize_track(audio)}]
      {nil, videos} -> [
          {main_manifest_name, build_master_playlist(nil, videos)} |
          videos |> Enum.map(& {"#{&1.header_name |> String.split(".") |> List.first()}.m3u8", serialize_track(&1)})
        ]
      {[audio], videos} -> List.flatten([
          {main_manifest_name, build_master_playlist([audio], videos)},
          {"audio.m3u8", serialize_track(audio)},
          videos |> Enum.map(& {"#{&1.header_name |> String.split(".") |> List.first()}.m3u8", serialize_track(&1)})
        ])
    end
  end

  defp calculate_bandwith(%Track{content_type: :video} = track) do
    total_size = Enum.map(track.segments, fn(segment) -> segment.bits end) |> Enum.sum()
    total_duration = track.segments |> Enum.map(& Ratio.to_float(&1.duration / Time.second())) |> Enum.sum()
    trunc(total_size / total_duration)
  end

  defp build_media_playlist_tag(%Track{content_type: :audio} = _)do
    """
    #EXT-X-MEDIA:TYPE=AUDIO,NAME="a",GROUP-ID="a",AUTOSELECT=YES,DEFAULT=YES,URI="audio.m3u8"
    """
  end

  defp build_media_playlist_tag(%Track{content_type: :video} = track) do
    """
    #EXT-X-STREAM-INF:CODECS="avc1.42e00a",BANDWIDTH=#{calculate_bandwith(track)}
    """
  end

  defp build_media_playlist_tag(%Track{content_type: :video} = track, audio_id) do
    """
    #EXT-X-STREAM-INF:CODECS="avc1.42e00a",BANDWIDTH=#{calculate_bandwith(track)},AUDIO=#{audio_id}
    """
  end

  defp build_master_playlist(audios, videos) do
    case {audios, videos} do
      {[audio], nil} ->
        "#{@master_playlist_header}" <> build_media_playlist_tag(audio)
      {nil, videos} -> [
          "#{@master_playlist_header}" |
          videos |> Enum.map(& build_media_playlist_tag(&1) <> "#{&1.header_name |> String.split(".") |> List.first()}.m3u8\n")
        ]|> Enum.join("")
      {[audio], videos} -> [
          "#{@master_playlist_header}" <> build_media_playlist_tag(audio) |
          videos |> Enum.map(& build_media_playlist_tag(&1, "a") <> "#{&1.header_name |> String.split(".") |> List.first()}.m3u8\n")
        ]|> Enum.join("")
    end
  end

  defp serialize_track(%Track{} = track) do
    use Ratio

    target_duration = Ratio.ceil(track.target_segment_duration / Time.second()) |> trunc()
    media_sequence = track.current_seq_num - Enum.count(track.segments)

    """
    #EXTM3U
    #EXT-X-VERSION:#{@version}
    #EXT-X-TARGETDURATION:#{target_duration}
    #EXT-X-MEDIA-SEQUENCE:#{media_sequence}
    #EXT-X-DISCONTINUITY-SEQUENCE:#{track.current_discontinuity_seq_num}
    #EXT-X-MAP:URI="#{track.header_name}"
    #{track.segments |> Enum.flat_map(&serialize_segment/1) |> Enum.join("\n")}
    #{if track.finished?, do: "#EXT-X-ENDLIST", else: ""}
    """
  end

  defp serialize_segment(segment) do
    time = Ratio.to_float(segment.duration / Time.second())

    Enum.flat_map(segment.attributes, &SegmentAttribute.serialize/1) ++
      ["#EXTINF:#{time},", segment.name]
  end
end
