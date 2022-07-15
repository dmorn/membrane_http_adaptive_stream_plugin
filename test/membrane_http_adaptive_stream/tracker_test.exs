defmodule Membrane.HTTPAdaptiveStream.TrackerTest do
  use ExUnit.Case

  alias Membrane.HTTPAdaptiveStream.{Loader, Tracker, HLS}
  alias Membrane.HTTPAdaptiveStream.Loader.FS
  alias Membrane.HTTPAdaptiveStream.Manifest.Track.Segment

  @manifest_base_path "./test/membrane_http_adaptive_stream/integration_test/fixtures/audio_multiple_video_tracks/"
  @loader Loader.new(%FS{base_path: @manifest_base_path}, HLS)

  defmodule OneMoreLoader do
    @behaviour Membrane.HTTPAdaptiveStream.Loader

    defstruct [:initial, max: 1, target_duration: 1]

    @impl true
    def init(config) do
      {:ok, pid} =
        Agent.start(fn ->
          %{
            initial: config.initial,
            max: config.max,
            calls: 0,
            target_duration: config.target_duration
          }
        end)

      pid
    end

    @impl true
    def load_manifest(_, _) do
      {:ok,
       """
       #EXTM3U
       #EXT-X-VERSION:7
       #EXT-X-INDEPENDENT-SEGMENTS
       #EXT-X-STREAM-INF:BANDWIDTH=725435,CODECS="avc1.42e00a",AUDIO="audio_default_id"
       one_more.m3u8
       """}
    end

    @impl true
    def load_track(pid, _) do
      config =
        Agent.get_and_update(pid, fn state ->
          {state, %{state | calls: state.calls + 1}}
        end)

      header = """
      #EXTM3U
      #EXT-X-VERSION:7
      #EXT-X-TARGETDURATION:#{config.target_duration}
      #EXT-X-MEDIA-SEQUENCE:0
      #EXT-X-DISCONTINUITY-SEQUENCE:0
      """

      calls = config.calls

      segs =
        Enum.map(Range.new(0, calls + config.initial), fn seq ->
          """
          #EXTINF:0.89,
          video_segment_#{seq}_video_720x480.m4s
          """
        end)

      tail =
        if calls == config.max do
          "#EXT-X-ENDLIST"
        else
          ""
        end

      {:ok, Enum.join([header] ++ segs ++ [tail], "\n")}
    end

    @impl true
    def load_segment(_, _) do
      {:error, "should not be called here"}
    end
  end

  describe "Tracker process" do
    defp default_track_config() do
      {:ok, manifest} = Loader.load_manifest(@loader, "index.m3u8")
      Map.get(manifest.track_configs, "video_video_720x480")
    end

    test "starts and exits on demand" do
      assert {:ok, pid} = Tracker.start_link(@loader)
      assert Process.alive?(pid)
      assert :ok = Tracker.stop(pid)
    end

    test "sends one message for each segment in a static track" do
      {:ok, pid} = Tracker.start_link(@loader)
      ref = Tracker.follow(pid, default_track_config())

      Enum.each(0..7, fn seq ->
        assert_receive {:segment, ^ref, {^seq, %Segment{}}}, 1000
      end)

      refute_received {:segment, ^ref, _}, 1000

      :ok = Tracker.stop(pid)
    end

    test "sends track termination message when track is finished" do
      {:ok, pid} = Tracker.start_link(@loader)
      ref = Tracker.follow(pid, default_track_config())

      assert_receive {:end_of_track, ^ref}, 1000

      :ok = Tracker.stop(pid)
    end

    test "keeps on sending updates when the playlist does" do
      loader = Loader.new(%OneMoreLoader{initial: 1, target_duration: 1}, HLS)
      {:ok, manifest} = Loader.load_manifest(loader, "one_more")
      track_config = Map.get(manifest.track_configs, "one_more")
      {:ok, pid} = Tracker.start_link(loader)
      ref = Tracker.follow(pid, track_config)

      assert_receive {:segment, ^ref, {0, %Segment{}}}, 100
      assert_receive {:segment, ^ref, {1, %Segment{}}}, 100

      # The tracker should wait `target_duration` seconds, reload the track
      # afterwards and detect that one more segment has been provied, together
      # with the termination tag.

      assert_receive {:segment, ^ref, {2, %Segment{}}}, 2000
      refute_received {:segment, ^ref, _}, 2000
      assert_receive {:end_of_track, ^ref}, 2000

      :ok = Tracker.stop(pid)
    end

    test "sends start of track message identifing first sequence number" do
      {:ok, pid} = Tracker.start_link(@loader)
      ref = Tracker.follow(pid, default_track_config())

      # NOTE: the sequence comes from track information. It would be better to
      # test this behaviour with a track that does not start with sequence
      # number == 0.
      assert_receive {:start_of_track, ^ref, 0}, 1000

      :ok = Tracker.stop(pid)
    end
  end
end
