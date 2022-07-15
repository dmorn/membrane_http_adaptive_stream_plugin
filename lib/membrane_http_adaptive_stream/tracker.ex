defmodule Membrane.HTTPAdaptiveStream.Tracker do
  use GenServer

  alias Membrane.HTTPAdaptiveStream.Loader
  alias Membrane.HTTPAdaptiveStream.Manifest.Track

  defstruct [:loader, following: %{}]

  defmodule Tracking do
    defstruct [:ref, :track_config, :notify, is_starting?: true, seq: 0]
  end

  def start_link(loader = %Loader{}, opts \\ []) do
    GenServer.start_link(__MODULE__, loader, opts)
  end

  def stop(pid), do: GenServer.stop(pid)

  def follow(pid, track_config = %Track.Config{}) do
    GenServer.call(pid, {:follow, track_config})
  end

  @impl true
  def init(loader) do
    {:ok, %__MODULE__{loader: loader}}
  end

  @impl true
  def handle_call({:follow, track_config}, {from, _}, state) do
    tracking = %Tracking{ref: make_ref(), track_config: track_config, notify: from}
    following = Map.put(state.following, tracking.ref, tracking)
    state = %__MODULE__{state | following: following}
    {:reply, tracking.ref, state, {:continue, {:refresh, tracking}}}
  end

  @impl true
  def handle_continue({:refresh, tracking}, state) do
    handle_refresh(tracking, state)
  end

  @impl true
  def handle_info({:refresh, tracking}, state) do
    handle_refresh(tracking, state)
  end

  defp handle_refresh(tracking, state) do
    {:ok, track} = Loader.load_track(state.loader, tracking.track_config)

    # Determine initial sequence number, sending the start_of_track message if
    # needed.
    tracking =
      if tracking.is_starting? do
        seq = track.current_seq_num
        send(tracking.notify, {:start_of_track, tracking.ref, seq})
        %Tracking{tracking | seq: seq, is_starting?: false}
      else
        tracking
      end

    {segs, last_seq} = segments_with_seq(track)

    # Send new segments only
    msgs =
      segs
      |> Enum.filter(fn {seq, _} -> seq >= tracking.seq end)
      |> Enum.map(fn {seq, seg} -> {:segment, tracking.ref, {seq, seg}} end)

    Enum.each(msgs, &send(tracking.notify, &1))

    # Schedule a new refresh if needed
    tracking = %Tracking{tracking | seq: last_seq}

    if track.finished? do
      send(tracking.notify, {:end_of_track, tracking.ref})
    else
      wait = Track.target_segment_duration(track, :milliseconds)
      Process.send_after(self(), {:refresh, tracking}, wait)
    end

    following = Map.put(state.following, tracking.ref, tracking)
    {:noreply, %__MODULE__{state | following: following}}
  end

  defp segments_with_seq(%Track{segments: segments, current_seq_num: start}) do
    Enum.map_reduce(segments, start, fn segment, seq ->
      {{seq, segment}, seq + 1}
    end)
  end
end
