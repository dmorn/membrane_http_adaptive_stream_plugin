defmodule Membrane.HTTPAdaptiveStream.Manifest do
  @moduledoc """
  Behaviour for manifest serialization.
  """
  use Bunch.Access
  alias __MODULE__.Track

  # NOTE(dmorn): I would consider putting the serialization/deserialization
  # behaviour into a separate module, leaving Track, Manifest and Segment for
  # holding the information the HLS files hold.

  @callback serialize(t) :: [{manifest_name :: String.t(), manifest_content :: String.t()}]

  @type t :: %__MODULE__{
          name: String.t(),
          module: module,
          version: pos_integer(),
          track_configs: %{(id :: any) => Track.Config.t()},
          tracks: %{(id :: any) => Track.t()}
        }

  @enforce_keys [:name, :module]
  defstruct @enforce_keys ++ [:version, tracks: %{}, track_configs: %{}]

  @doc """
  Adds a track to the manifest.

  Returns the name under which the header file should be stored.
  """
  @spec add_track(t, Track.Config.t()) :: {header_name :: String.t(), t}
  def add_track(manifest, %Track.Config{} = config) do
    track = Track.new(config)
    manifest = %__MODULE__{manifest | tracks: Map.put(manifest.tracks, config.id, track)}
    {track.header_name, manifest}
  end

  @doc """
  Adds a track configuration to the manifest. It is used when deserializing a
  Manifest file. At that time, only the configuration is known. With that
  information, it is possible to load the actual track finally inserting it
  into the manifest.
  """
  def add_track_config(manifest, %Track.Config{} = config) do
    %__MODULE__{manifest | track_configs: Map.put(manifest.track_configs, config.id, config)}
  end

  @spec add_segment(
          t,
          track_id :: Track.id_t(),
          Track.segment_duration_t(),
          Track.segment_bytes_size_t(),
          list(__MODULE__.SegmentAttribute.t())
        ) ::
          {{to_add_name :: String.t(), to_remove_names :: Track.to_remove_names_t()}, t}
  def add_segment(%__MODULE__{} = manifest, track_id, duration, bytes_size, attributes \\ []) do
    get_and_update_in(
      manifest,
      [:tracks, track_id],
      &Track.add_segment(&1, duration, bytes_size, attributes)
    )
  end

  @spec serialize(t) :: [{name :: String.t(), manifest :: String.t()}]
  def serialize(%__MODULE__{module: module} = manifest) do
    module.serialize(manifest)
  end

  @spec has_track?(t(), Track.id_t()) :: boolean()
  def has_track?(%__MODULE__{tracks: tracks}, track_id), do: Map.has_key?(tracks, track_id)

  @doc """
  Append a discontinuity to the track.

  This will inform the player that eg. the parameters of the encoder changed and allow you to provide a new MP4 header.
  For details on discontinuities refer to [RFC 8216](https://datatracker.ietf.org/doc/html/rfc8216).
  """
  @spec discontinue_track(t(), Track.id_t()) :: {header_name :: String.t(), t()}
  def discontinue_track(%__MODULE__{} = manifest, track_id) do
    get_and_update_in(
      manifest,
      [:tracks, track_id],
      &Track.discontinue/1
    )
  end

  @spec finish(t, Track.id_t()) :: t
  def finish(%__MODULE__{} = manifest, track_id) do
    update_in(manifest, [:tracks, track_id], &Track.finish/1)
  end

  @doc """
  Restores all the stale segments in all tracks.

  All the tracks must be configured to be persisted beforehand, otherwise this function will raise
  """
  @spec from_beginning(t()) :: t
  def from_beginning(%__MODULE__{} = manifest) do
    tracks = Bunch.Map.map_values(manifest.tracks, &Track.from_beginning/1)
    %__MODULE__{manifest | tracks: tracks}
  end

  @doc """
  Returns stale and current segments' names from all tracks
  """
  @spec all_segments(t) :: [[track_name :: String.t()]]
  def all_segments(%__MODULE__{} = manifest) do
    manifest.tracks |> Map.values() |> Enum.flat_map(&Track.all_segments/1)
  end
end
