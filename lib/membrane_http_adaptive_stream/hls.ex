defmodule Membrane.HTTPAdaptiveStream.HLS do
  @moduledoc """
  `Membrane.HTTPAdaptiveStream.Manifest` implementation for HTTP Live Streaming.

  Currently supports up to one audio and video stream.
  """
  @behaviour Membrane.HTTPAdaptiveStream.Manifest
  @behaviour Membrane.HTTPAdaptiveStream.Deserializer

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
          |> Enum.map(&{build_media_playlist_path(&1), serialize_track(&1)})
        ])

      # Handle audio track and multiple renditions of video
      %{audio: [audio], video: videos} ->
        List.flatten([
          {main_manifest_name, build_master_playlist(manifest, {audio, videos})},
          {"audio.m3u8", serialize_track(audio)},
          videos
          |> Enum.filter(&(&1.segments != @empty_segments))
          |> Enum.map(&{build_media_playlist_path(&1), serialize_track(&1)})
        ])

      # Handle only audio, without any video tracks
      %{audio: [audio]} ->
        [
          {main_manifest_name, build_master_playlist(manifest, {audio, nil})},
          {"audio.m3u8", serialize_track(audio)}
        ]

      # Handle video without audio
      %{video: videos} ->
        List.flatten([
          {main_manifest_name, build_master_playlist(manifest, {nil, videos})},
          videos
          |> Enum.filter(&(&1.segments != @empty_segments))
          |> Enum.map(&{build_media_playlist_path(&1), serialize_track(&1)})
        ])
    end
  end

  @impl true
  def deserialize_master_manifest("", _data),
    do: raise(ArgumentError, "No manifest name was provided")

  def deserialize_master_manifest(name, _data) when not is_binary(name),
    do: raise(ArgumentError, "Manifest name has to be a binary")

  def deserialize_master_manifest(name, "#EXTM3U" <> data) do
    header_config =
      capture_config(data, %{}, [
        {:version, ~r/#EXT-X-VERSION:(?<version>\d+)/, &String.to_integer(&1)}
      ])

    version = Map.get(header_config, :version)
    manifest = %Manifest{module: __MODULE__, name: name, version: version}

    matchers = [
      {:bandwidth, ~r/BANDWIDTH=(?<bandwidth>\d+)/, &String.to_integer(&1)},
      {:codecs, ~r/CODECS="(?<codecs>[\w|\.|,]*)"/, &String.split(&1, ",")},
      {:frame_rate, ~r/FRAME-RATE=(?<frame_rate>\d+\.?\d*)/, &String.to_float(&1)},
      {:track_name, ~r/.*\s*(?<track_name>.*\..*$)/,
       fn raw ->
         uri = URI.parse(raw)
         name = String.trim_trailing(uri.path, ".m3u8")
         query = uri.query
         [{:track_name, name}, {:query, query}]
       end},
      {:resolution, ~r/RESOLUTION=(?<resolution>\d+x\d+)/,
       fn raw ->
         raw
         |> String.split("x")
         |> Enum.map(&String.to_integer/1)
       end}
    ]

    track_configs =
      ~r/#EXT-X-STREAM-INF:.*\s*.*/
      |> Regex.scan(data)
      |> Enum.map(fn [line] -> capture_config(line, %{}, matchers) end)
      |> Enum.map(fn config ->
        id = Map.get(config, :track_name)
        Map.put(config, :id, id)
      end)
      |> Enum.map(fn config -> struct(Manifest.Track.Config, config) end)

    subtitle_matchers = [
      {:id, ~r/GROUP-ID="(?<id>.*)"/, fn raw -> raw end},
      {:language, ~r/LANGUAGE="(?<language>[\w|\-]*)"/, fn raw -> raw end},
      {:uri, ~r/URI="(?<uri>.*)"/,
       fn raw ->
         uri = URI.parse(raw)
         name = String.trim_trailing(uri.path, ".m3u8")
         query = uri.query
         [{:track_name, name}, {:query, query}]
       end}
    ]

    subtitle_track_configs =
      ~r/#EXT-X-MEDIA:TYPE=SUBTITLES,.*/
      |> Regex.scan(data)
      |> Enum.map(fn [line] -> String.split(line, ",") end)
      # The line it split into its fields as otherwise it is difficult to match
      # the URI field w/o matching the rest of the line.
      |> Enum.map(fn fields ->
        fields
        |> Enum.map(fn field -> capture_config(field, %{}, subtitle_matchers) end)
        |> Enum.reduce(%{}, &Map.merge(&1, &2))
      end)
      |> Enum.map(fn config -> struct(Manifest.Track.Config, config) end)

    Enum.reduce(track_configs ++ subtitle_track_configs, manifest, fn config, manifest ->
      Manifest.add_track_config(manifest, config)
    end)
  end

  def deserialize_master_manifest(name, _data) do
    raise ArgumentError,
          "Could not deserialize manifest #{inspect(name)} as it contains invalid data"
  end

  @impl true
  def deserialize_media_track(nil, _data) do
    raise ArgumentError, "No media track configuration provided"
  end

  def deserialize_media_track(track_config, "#EXTM3U" <> data) do
    track = Manifest.Track.new(track_config)

    header_matchers = [
      {:version, ~r/#EXT-X-VERSION:(?<version>\d+)/, &String.to_integer(&1)},
      {:target_segment_duration, ~r/#EXT-X-TARGETDURATION:(?<target_segment_duration>\d+)/,
       fn raw ->
         String.to_integer(raw)
       end},
      {:current_seq_num, ~r/#EXT-X-MEDIA-SEQUENCE:(?<current_seq_num>\d+)/,
       fn raw ->
         String.to_integer(raw)
       end},
      {:current_discontinuity_seq_num,
       ~r/#EXT-X-DISCONTINUITY-SEQUENCE:(?<current_discontinuity_seq_num>\d+)/,
       fn raw ->
         String.to_integer(raw)
       end},
      {:segment_extension, ~r/#EXTINF:.*\s*(?<segment_extension>.*)/, &Path.extname(&1)}
    ]

    header_config = capture_config(data, %{}, header_matchers)

    track =
      Enum.reduce(header_config, track, fn {key, val}, track ->
        Map.put(track, key, val)
      end)

    matchers = [
      {:name, ~r/.*\s*(?<name>.*)/,
       fn raw ->
         uri = URI.parse(raw)
         ext = Path.extname(uri.path)
         name = String.trim_trailing(uri.path, ext)
         [{:name, name}, {:query, uri.query}, {:extension, ext}]
       end},
      {:duration, ~r/#EXTINF:(?<duration>\d+\.?\d*),/, &String.to_float(&1)}
    ]

    # Avoids stale computations
    track = %Manifest.Track{track | target_window_duration: :infinity}

    segments =
      ~r/#EXTINF:.*\s*.*/
      |> Regex.scan(data)
      |> Enum.map(fn [line] -> capture_config(line, %{}, matchers) end)
      |> Enum.map(fn config -> struct(Manifest.Track.Segment, config) end)

    track =
      Enum.reduce(segments, track, fn segment, track ->
        {_, track} = Manifest.Track.add_segment(track, segment)
        track
      end)

    if Regex.match?(~r/#EXT-X-ENDLIST/, data) do
      Manifest.Track.finish(track)
    else
      track
    end
  end

  def deserialize_media_track(_other, _data),
    do: raise(ArgumentError, "Invalid arguments provided")

  defp capture_config(_line, config, []), do: config

  defp capture_config(line, config, [matcher | others]) do
    {id, regex, post_process} = matcher

    config =
      case Regex.named_captures(regex, line) do
        nil ->
          config

        captures ->
          new_config =
            captures
            |> Map.get(Atom.to_string(id))
            |> post_process.()
            |> handle_capture_post_process(id, %{})

          Map.merge(config, new_config)
      end

    capture_config(line, config, others)
  end

  defp handle_capture_post_process([{_key, _val} | _values] = values, _id, config) do
    Enum.reduce(values, config, fn {key, val}, config ->
      Map.put(config, key, val)
    end)
  end

  defp handle_capture_post_process(value, id, config) do
    Map.put(config, id, value)
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

  defp track_version(%Manifest.Track{version: nil}), do: @default_version
  defp track_version(%Manifest.Track{version: version}), do: version

  defp serialize_track(%Manifest.Track{} = track) do
    version = track_version(track)
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
