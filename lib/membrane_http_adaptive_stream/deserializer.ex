defmodule Membrane.HTTPAdaptiveStream.Deserializer do
  alias Membrane.HTTPAdaptiveStream.Manifest

  @type id_t :: String.t()
  @type content_t :: String.t()

  @callback deserialize_master_manifest(id_t, content_t) :: Manifest.t()
  @callback deserialize_media_track(Manifest.Track.Config.t(), content_t) :: Manifest.Track.t()
end
