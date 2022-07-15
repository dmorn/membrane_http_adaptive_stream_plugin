defmodule Membrane.HTTPAdaptiveStream.Loader do
  @moduledoc """
  Defines a module that is capable of loading the contents
  """

  alias Membrane.HTTPAdaptiveStream.Deserializer
  alias Membrane.HTTPAdaptiveStream.Manifest
  alias Membrane.HTTPAdaptiveStream.Manifest.Track

  @type config_t :: struct
  @type state_t :: any

  @type ok_t :: {:ok, String.t() | binary()}
  @type error_t :: {:error, any}
  @type callback_result_t :: ok_t | error_t

  @doc """
  Generates the loader state based on the configuration struct.
  """
  @callback init(config_t) :: state_t

  @callback load_manifest(state_t, String.t()) :: callback_result_t
  @callback load_track(state_t, Track.Config.t()) :: callback_result_t
  @callback load_segment(state_t, Track.Segment.t()) :: callback_result_t

  defstruct [:loader_impl, :impl_state, :deserializer]
  @opaque t :: %__MODULE__{loader_impl: module, impl_state: any, deserializer: Deserializer.t()}

  @doc """
  Creates a Loader backed by the provided module implemetation configuration.
  """
  @spec new(config_t, Deserializer.t()) :: t
  def new(%loader_impl{} = loader_config, deserializer) do
    %__MODULE__{
      loader_impl: loader_impl,
      impl_state: loader_impl.init(loader_config),
      deserializer: deserializer
    }
  end

  @spec load_manifest(t, String.t()) :: {:ok, Manifest.t()} | {:error, any}
  def load_manifest(loader, location) do
    load_fun = fn -> loader.loader_impl.load_manifest(loader.impl_state, location) end

    decode_fun = fn data ->
      manifest_name = Path.basename(location)
      loader.deserializer.deserialize_master_manifest(manifest_name, data)
    end

    load(load_fun, decode_fun)
  end

  @spec load_track(t, Track.Config.t()) :: {:ok, Track.t()} | {:error, any}
  def load_track(loader, %Track.Config{} = config) do
    load_fun = fn -> loader.loader_impl.load_track(loader.impl_state, config) end
    decode_fun = fn data -> loader.deserializer.deserialize_media_track(config, data) end
    load(load_fun, decode_fun)
  end

  @spec load_segment(t, Track.Segment.t()) :: callback_result_t
  def load_segment(loader, %Track.Segment{} = segment) do
    loader.loader_impl.load_segment(loader.impl_state, segment)
  end

  defp load(load_fun, decode_fun) do
    case load_fun.() do
      {:ok, content} -> {:ok, decode_fun.(content)}
      error = {:error, _reason} -> error
    end
  end
end
