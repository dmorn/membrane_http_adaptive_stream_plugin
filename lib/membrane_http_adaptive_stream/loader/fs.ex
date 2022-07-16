defmodule Membrane.HTTPAdaptiveStream.Loader.FS do
  @behaviour Membrane.HTTPAdaptiveStream.Loader

  alias Membrane.HTTPAdaptiveStream.Manifest.Track
  alias Membrane.HTTPAdaptiveStream.Manifest.Track.{Segment, Config}

  @enforce_keys [:location]
  defstruct @enforce_keys ++ [:dirname, :basename, :manifest_ext]

  @impl true
  def init(config = %__MODULE__{location: location}) do
    basename = Path.basename(location)
    dirname = Path.dirname(location)
    ext = Path.extname(basename)
    %__MODULE__{config | basename: basename, dirname: dirname, manifest_ext: ext}
  end

  @impl true
  def load_manifest(%__MODULE__{dirname: dir, basename: manifest}) do
    load([dir, manifest])
  end

  @impl true
  def load_track(%__MODULE__{dirname: dir, manifest_ext: ext}, %Config{track_name: name}) do
    load([dir, "#{name}#{ext}"])
  end

  @impl true
  def load_segment(%__MODULE__{dirname: dir}, %Segment{} = segment) do
    %Track.Segment{name: name, extension: ext} = segment
    load([dir, "#{name}#{ext}"])
  end

  @impl true
  def manifest_name(%__MODULE__{basename: name, manifest_ext: ext}) do
    String.trim_leading(name, ext)
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
