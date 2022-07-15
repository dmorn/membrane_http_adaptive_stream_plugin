defmodule Membrane.HTTPAdaptiveStream.Loader.FS do
  @behaviour Membrane.HTTPAdaptiveStream.Loader

  alias Membrane.HTTPAdaptiveStream.Manifest.Track

  defstruct [:base_path]

  @impl true
  def init(config), do: config

  @impl true
  def load_manifest(%__MODULE__{}, _location) do
    {:error, :not_implemented}
  end

  @impl true
  def load_track(%__MODULE__{}, %Track.Config{} = _config) do
    {:error, :not_implemented}
  end
end
