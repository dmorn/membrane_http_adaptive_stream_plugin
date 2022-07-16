defmodule Membrane.HTTPAdaptiveStream.Loader.HTTP do
  @behaviour Membrane.HTTPAdaptiveStream.Loader

  alias Membrane.HTTPAdaptiveStream.Manifest.Track
  alias Membrane.HTTPAdaptiveStream.Manifest.Track.{Segment, Config}

  @enforce_keys [:url]
  defstruct @enforce_keys ++ [:client, :manifest_name, :manifest_ext]

  @impl true
  def init(config = %__MODULE__{url: url}) do
    uri = URI.parse(url)
    base_url = "#{uri.scheme}://#{uri.host}#{Path.dirname(uri.path)}"
    manifest = Path.basename(uri.path)
    manifest_ext = Path.extname(manifest)
    middleware = [
      {Tesla.Middleware.BaseUrl, base_url}
    ]

    %__MODULE__{config |
      client: Tesla.client(middleware),
      manifest_name: String.trim_trailing(manifest, manifest_ext),
      manifest_ext: manifest_ext,
    }
  end

  @impl true
  def load_manifest(loader = %__MODULE__{manifest_name: name, manifest_ext: ext}) do
    load(loader, "#{name}#{ext}")
  end

  @impl true
  def manifest_name(%__MODULE__{manifest_name: name}), do: name

  @impl true
  def load_track(loader = %__MODULE__{manifest_ext: ext}, %Config{track_name: name, query: query_raw}) do
    query = decode_query(query_raw)
    load(loader, "#{name}#{ext}", query: query)
  end

  @impl true
  def load_segment(%__MODULE__{client: _client}, %Segment{} = _segment) do
    {:error, "HTTP adapter is not yet able to load segments"}
  end

  defp decode_query(nil), do: []
  defp decode_query(raw) when is_binary(raw) do
    raw
    |> URI.decode_query()
    |> Enum.into([])
  end

  defp load(%__MODULE__{client: client}, url, opts \\ []) do
    case Tesla.get(client, url, opts) do
      error = {:error, _reason} -> error
      {:ok, %Tesla.Env{body: body}} -> {:ok, body}
    end
  end
end
