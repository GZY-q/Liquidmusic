import Foundation
import Observation

@MainActor @Observable
final class LyricsModel {
    private(set) var document: LyricsDocument?
    private(set) var isLoading = false
    private(set) var error: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let reader: any LyricsReading

    init(reader: any LyricsReading = LyricsReader(), document: LyricsDocument? = nil) {
        self.reader = reader
        self.document = document
    }

    func load(track: Track, file: URL? = nil) async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        generation = request
        document = nil
        error = nil
        isLoading = true
        do {
            let result: LyricsDocument?
            if let file { result = try await reader.readFile(file) }
            else { result = try await reader.read(for: track) }
            guard !Task.isCancelled, generation == request else { return }
            document = result
            if file != nil, result == nil { error = LyricsError.empty.localizedDescription }
            isLoading = false
        } catch {
            guard !Task.isCancelled, generation == request else { return }
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func cancel() {
        generation = UUID()
        isLoading = false
        document = nil
        error = nil
    }
}
