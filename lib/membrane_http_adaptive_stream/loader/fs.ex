defmodule Membrane.HTTPAdaptiveStream.Loader.FS do
  @behaviour Membrane.HTTPAdaptiveStream.Loader

  alias Membrane.HTTPAdaptiveStream.Manifest.Track
  alias Membrane.HTTPAdaptiveStream.Manifest.Track.{Segment, Config}

  defstruct [:base_path]

  @impl true
  def init(config), do: config

  @impl true
  def load_manifest(%__MODULE__{base_path: base}, location) do
    load([base, location])
  end

  @impl true
  def load_track(%__MODULE__{base_path: base}, %Config{track_name: name}) do
    load([base, "#{name}.m3u8"])
  end

  @impl true
  def load_segment(%__MODULE__{base_path: base}, %Segment{} = segment) do
    %Track.Segment{name: name, extension: ext} = segment
    load([base, "#{name}#{ext}"])
  end

  defp load(path) when is_list(path) do
    path
    |> Path.join()
    |> load()
  end

  defp load(path) when is_binary(path) do
    File.read(path)
  end
end
