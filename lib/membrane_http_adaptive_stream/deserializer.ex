defmodule Membrane.HTTPAdaptiveStream.Deserializer do
  alias Membrane.HTTPAdaptiveStream.Manifest

  @callback deserialize_master_manifest(String.t(), String.t()) :: Manifest.t()
  @callback deserialize_media_track(Manifest.Track.t(), String.t()) :: Manifest.Track.t()
end
