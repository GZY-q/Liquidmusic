import SwiftUI

struct PlaybackProgressView: View {
    let playback: PlaybackController
    var showsTimeLabels = false
    var controlSize: ControlSize = .mini
    @State private var scrub = PlaybackScrubState()

    var body: some View {
        VStack(spacing: 0) {
            slider.frame(height: controlSize == .mini ? 18 : 28)
            if showsTimeLabels {
                HStack {
                    Text(Track.timeText(scrub.displayedPosition(elapsed: playback.elapsed, duration: playback.duration)))
                    Spacer()
                    Text("−\(Track.timeText(max(0, playback.duration - scrub.displayedPosition(elapsed: playback.elapsed, duration: playback.duration))))")
                }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: playback.queue.currentEntryID) { scrub.cancel() }
    }

    private var slider: some View {
        let entryID = playback.queue.currentEntryID
        return SlimPlaybackSlider(value: Binding(get: {
                scrub.displayedPosition(elapsed: playback.elapsed, duration: playback.duration)
            }, set: { value in
                guard entryID == playback.queue.currentEntryID else { return }
                if let position = scrub.update(value, entryID: entryID, duration: playback.duration) {
                    playback.seek(to: position)
                }
            }), maximum: playback.duration, isEnabled: playback.canSeek, onEditingChanged: { editing in
                // 旧 Slider 的结束回调不能把上一首的拖动位置写到新条目。
                guard entryID == playback.queue.currentEntryID else { return }
                if editing { scrub.begin(entryID: entryID, elapsed: playback.elapsed, duration: playback.duration) }
                else if let position = scrub.finish(entryID: entryID, duration: playback.duration) {
                    playback.seek(to: position)
                }
            }, controlSize: controlSize)
            .id(entryID)
    }
}

#Preview {
    PlaybackProgressView(playback: PlaybackController(connectSystemMedia: false)).padding().frame(width: 400)
}
