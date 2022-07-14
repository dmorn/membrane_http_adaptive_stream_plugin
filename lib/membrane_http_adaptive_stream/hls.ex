defmodule Membrane.HTTPAdaptiveStream.HLS do
  @moduledoc """
  `Membrane.HTTPAdaptiveStream.Manifest` implementation for HTTP Live Streaming.

  Currently supports up to one audio and video stream.
  """
  @behaviour Membrane.HTTPAdaptiveStream.Manifest

  use Ratio

  alias Membrane.HTTPAdaptiveStream.{BandwidthCalculator, Manifest}
  alias Membrane.Time

  @default_version 7

  @empty_segments Qex.new()
  @default_audio_track_id "audio_default_id"
  @default_audio_track_name "audio_default_name"

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
    tracks_by_content =
      manifest.tracks
      |> Map.values()
      |> Enum.group_by(& &1.content_type)

    main_manifest_name = "#{manifest.name}.m3u8"

    if length(Map.get(tracks_by_content, :audio, [])) > 1 do
      raise ArgumentError, message: "Multiple audio tracks are not currently supported."
    end

    # Depending on tracks present in the manifest, generate master playlist and playlists for each track
    case tracks_by_content do
      # Handling muxed content - where audio and video is contained in a single CMAF Track
      %{muxed: muxed_tracks} ->
        List.flatten([
          {main_manifest_name, build_master_playlist(manifest, {nil, muxed_tracks})},
          muxed_tracks
          |> Enum.filter(&(&1.segments != @empty_segments))
          |> Enum.map(&{build_media_playlist_path(&1), serialize_track(manifest, &1)})
        ])

      # Handle audio track and multiple renditions of video
      %{audio: [audio], video: videos} ->
        List.flatten([
          {main_manifest_name, build_master_playlist(manifest, {audio, videos})},
          {"audio.m3u8", serialize_track(manifest, audio)},
          videos
          |> Enum.filter(&(&1.segments != @empty_segments))
          |> Enum.map(&{build_media_playlist_path(&1), serialize_track(manifest, &1)})
        ])

      # Handle only audio, without any video tracks
      %{audio: [audio]} ->
        [
          {main_manifest_name, build_master_playlist(manifest, {audio, nil})},
          {"audio.m3u8", serialize_track(manifest, audio)}
        ]

      # Handle video without audio
      %{video: videos} ->
        List.flatten([
          {main_manifest_name, build_master_playlist(manifest, {nil, videos})},
          videos
          |> Enum.filter(&(&1.segments != @empty_segments))
          |> Enum.map(&{build_media_playlist_path(&1), serialize_track(manifest, &1)})
        ])
    end
  end

  defp parse_track_config(_line, config, []), do: struct(Manifest.Track.Config, config)
  defp parse_track_config(line, config, [matcher | others]) do
    {id, regex, post_process} = matcher
    config = case Regex.named_captures(regex, line) do
      nil ->
        config
      captures ->
        value =
          captures
          |> Map.get(Atom.to_string(id))
          |> post_process.()

        Map.put(config, id, value)
    end
    parse_track_config(line, config, others)
  end

  @spec deserialize(String.t(), String.t()) :: Manifest.t()
  def deserialize("", _data), do: raise(ArgumentError, "No manifest name was provided")

  def deserialize(name, _data) when not is_binary(name),
    do: raise(ArgumentError, "Manifest name has to be a binary")

  def deserialize(name, "#EXTM3U" <> data) do
    # Final s modifier activates "dotall"
    r = ~r/^\s*#EXT-X-VERSION\:(?<version>\d+)\s*(?<data>.*)$/s
    %{"version" => version_raw, "data" => data} = Regex.named_captures(r, data)
    version = String.to_integer(version_raw)

    matchers = [
      {:bandwidth, ~r/BANDWIDTH=(?<bandwidth>\d+)/, fn raw ->
        String.to_integer(raw)
      end},
      {:codecs, ~r/CODECS="(?<codecs>.*)"/, fn raw ->
        String.split(raw, ",")
      end},
      {:track_name, ~r/.*\s*(?<track_name>.*\.m3u8)/, fn raw ->
        String.trim_trailing(raw, ".m3u8")
      end},
      {:resolution, ~r/RESOLUTION=(?<resolution>\d+x\d+)/, fn raw ->
        raw
        |> String.split("x")
        |> Enum.map(&String.to_integer/1)
      end},
      {:frame_rate, ~r/FRAME-RATE=(?<frame_rate>\d+\.?\d*)/, fn raw ->
        String.to_float(raw)
      end}
    ]

    track_configs =
      ~r/#EXT-X-STREAM-INF:.*\s*.*\.m3u8/
      |> Regex.scan(data)
      |> Enum.map(fn [line] -> parse_track_config(line, %{}, matchers) end)
      |> Enum.map(fn config ->
        id = Map.get(config, :track_name)
        Map.put(config, :id, id)
      end)

    manifest = %Manifest{module: __MODULE__, name: name, version: version}

    Enum.reduce(track_configs, manifest, fn config, manifest ->
      {_, manifest} = Manifest.add_track(manifest, config)
      manifest
    end)
  end

  def deserialize(name, _data) do
    raise ArgumentError,
          "Could not deserialize manifest #{inspect(name)} as it contains invalid data"
  end

  defp build_media_playlist_path(%Manifest.Track{} = track) do
    [track.content_type, "_", track.track_name, ".m3u8"] |> Enum.join("")
  end

  defp build_media_playlist_tag(%Manifest.Track{} = track) do
    case track do
      %Manifest.Track{content_type: :audio} ->
        """
        #EXT-X-MEDIA:TYPE=AUDIO,NAME="#{@default_audio_track_name}",GROUP-ID="#{@default_audio_track_id}",AUTOSELECT=YES,DEFAULT=YES,URI="audio.m3u8"
        """
        |> String.trim()

      %Manifest.Track{content_type: type} when type in [:video, :muxed] ->
        """
        #EXT-X-STREAM-INF:BANDWIDTH=#{BandwidthCalculator.calculate_bandwidth(track)},CODECS="avc1.42e00a"
        """
        |> String.trim()
    end
  end

  defp build_master_playlist_header(manifest) do
    version = manifest_version(manifest)

    """
    #EXTM3U
    #EXT-X-VERSION:#{version}
    #EXT-X-INDEPENDENT-SEGMENTS
    """
    |> String.trim()
  end

  defp build_master_playlist(manifest, tracks) do
    master_playlist_header = build_master_playlist_header(manifest)

    case tracks do
      {audio, nil} ->
        [master_playlist_header, build_media_playlist_tag(audio)]
        |> Enum.join("")

      {nil, videos} ->
        [
          master_playlist_header
          | videos
            |> Enum.filter(&(&1.segments != @empty_segments))
            |> Enum.flat_map(&[build_media_playlist_tag(&1), build_media_playlist_path(&1)])
        ]
        |> Enum.join("\n")

      {audio, videos} ->
        video_tracks =
          videos
          |> Enum.filter(&(&1.segments != @empty_segments))
          |> Enum.flat_map(
            &[
              "#{build_media_playlist_tag(&1)},AUDIO=\"#{@default_audio_track_id}\"",
              build_media_playlist_path(&1)
            ]
          )

        [
          master_playlist_header,
          build_media_playlist_tag(audio),
          video_tracks
        ]
        |> List.flatten()
        |> Enum.join("\n")
    end
  end

  defp manifest_version(%Manifest{version: nil}), do: @default_version
  defp manifest_version(%Manifest{version: version}), do: version

  defp serialize_track(manifest, %Manifest.Track{} = track) do
    version = manifest_version(manifest)
    target_duration = Ratio.ceil(track.target_segment_duration / Time.second()) |> trunc()

    """
    #EXTM3U
    #EXT-X-VERSION:#{version}
    #EXT-X-TARGETDURATION:#{target_duration}
    #EXT-X-MEDIA-SEQUENCE:#{track.current_seq_num}
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
