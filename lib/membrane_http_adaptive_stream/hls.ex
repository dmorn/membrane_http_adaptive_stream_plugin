defmodule Membrane.HTTPAdaptiveStream.HLS do
  @moduledoc """
  `Membrane.HTTPAdaptiveStream.Manifest` implementation for HLS.

  Currently supports up to one audio and video stream.
  """
  alias Membrane.HTTPAdaptiveStream.Manifest
  alias Membrane.HTTPAdaptiveStream.Manifest.Track
  alias Membrane.Time

  @behaviour Manifest

  @version 7

  @av_manifest """
  #EXTM3U
  #EXT-X-VERSION:#{@version}
  #EXT-X-INDEPENDENT-SEGMENTS
  #EXT-X-STREAM-INF:BANDWIDTH=2560000,CODECS="avc1.42e00a",AUDIO="a"
  video.m3u8
  #EXT-X-MEDIA:TYPE=AUDIO,NAME="a",GROUP-ID="a",AUTOSELECT=YES,DEFAULT=YES,URI="audio.m3u8"
  """

  @impl true
  def serialize(%Manifest{} = manifest) do
    tracks_by_content = manifest.tracks |> Map.values() |> Enum.group_by(& &1.content_type)
    main_manifest_name = "#{manifest.name}.m3u8"

    case {tracks_by_content[:audio], tracks_by_content[:video]} do
      {[audio], [video]} ->
        [
          {main_manifest_name, @av_manifest},
          {"audio.m3u8", serialize_track(audio)},
          {"video.m3u8", serialize_track(video)}
        ]

      {[audio], nil} ->
        [{main_manifest_name, serialize_track(audio)}]

      {nil, [video]} ->
        [{main_manifest_name, serialize_track(video)}]
    end
  end

  defp serialize_track(%Track{} = track) do
    use Ratio

    target_duration = Ratio.ceil(track.target_segment_duration / Time.second()) |> trunc
    media_sequence = track.current_seq_num - Enum.count(track.segments)

    """
    #EXTM3U
    #EXT-X-VERSION:#{@version}
    #EXT-X-TARGETDURATION:#{target_duration}
    #EXT-X-MEDIA-SEQUENCE:#{media_sequence}
    #EXT-X-MAP:URI="#{track.header_name}"
    #{
      track.segments
      |> Enum.flat_map(&serialize_segment/1)
      |> Enum.join("\n")
    }
    #{if track.finished?, do: "#EXT-X-ENDLIST", else: ""}
    """
  end

  defp serialize_segment(%{name: name, duration: duration, attrs: attrs}) do
    (attrs |> Enum.map(&serialize_segment_attr/1)) ++ ["#EXTINF:#{Ratio.to_float(Ratio./(duration, Time.second()))},", name]
  end

  defp serialize_segment_attr({:program_date_time, datetime}), do:
    "#EXT-X-PROGRAM-DATE-TIME:#{DateTime.truncate(datetime, :millisecond) |> DateTime.to_iso8601()}"

  defp serialize_segment_attr({:date_range, fields}) do
    parsed_fields =
      fields
      |> Enum.map(fn entry ->
        case entry do
          {:id, id} -> {:id, "ID=\"#{id}\""}
          {:class, class} -> {:class, "CLASS=\"#{class}\""}
          {:start_date, start_date} -> {:start_date, "START-DATE=\"#{DateTime.truncate(start_date, :millisecond) |> DateTime.to_iso8601()}\""}
          {:end_on_next, val} -> {:end_on_next, "END-ON-NEXT=#{val}"}
          {:duration, val} -> {:duration, "DURATION=#{val}"}
          {param, val} ->
            param = param |> Atom.to_string() |> String.split("_") |> Enum.map(& String.upcase/1) |> Enum.join("-")

            {param, "X-#{param}=\"#{val}\""}
        end
      end)
      |> Enum.into(%{})

    seq_fields = [:id, :class, :start_date, :end_on_next]

    rest_fields = Map.drop(parsed_fields, seq_fields)

    fields = ((seq_fields |> Enum.map(& Map.get(parsed_fields, &1))) ++ (rest_fields |> Map.values())) |> Enum.reject(&is_nil/1) |> Enum.join(",")

    "#EXT-X-DATERANGE:#{fields}"
  end
end
