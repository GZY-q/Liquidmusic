import SwiftUI

struct PlaybackProgressView: View {
    let playback: PlaybackController
    @State private var scrub = PlaybackScrubState()

    var body: some View {
        let entryID = playback.queue.currentEntryID
        let position = scrub.displayedPosition(elapsed: playback.elapsed, duration: playback.duration)
        HStack(spacing: 8) {
            Text(Track.timeText(position)).monospacedDigit().frame(minWidth: 35, alignment: .trailing)
            Slider(value: Binding(get: {
                scrub.displayedPosition(elapsed: playback.elapsed, duration: playback.duration)
            }, set: { value in
                guard entryID == playback.queue.currentEntryID else { return }
                if let position = scrub.update(value, entryID: entryID, duration: playback.duration) {
                    playback.seek(to: position)
                }
            }), in: 0...max(playback.duration, 1), onEditingChanged: { editing in
                // 旧 Slider 的结束回调不能把上一首的拖动位置写到新条目。
                guard entryID == playback.queue.currentEntryID else { return }
                if editing { scrub.begin(entryID: entryID, elapsed: playback.elapsed, duration: playback.duration) }
                else if let position = scrub.finish(entryID: entryID, duration: playback.duration) {
                    playback.seek(to: position)
                }
            })
            .id(entryID)
            .accessibilityLabel("播放进度")
            .accessibilityValue("已播放 \(Track.timeText(position))，共 \(Track.timeText(playback.duration))")
            .disabled(!playback.canSeek)
            Text("−" + Track.timeText(max(0, playback.duration - position)))
                .monospacedDigit().frame(minWidth: 40, alignment: .leading)
        }
        .font(.caption2).foregroundStyle(.secondary)
        .onChange(of: entryID) { scrub.cancel() }
    }
}

#Preview {
    PlaybackProgressView(playback: PlaybackController(connectSystemMedia: false)).padding().frame(width: 400)
}
