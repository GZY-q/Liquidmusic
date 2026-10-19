import SwiftUI

struct ArtistsView: View {
    let artists: [LibraryArtist]
    let onOpen: (LibraryArtist) -> Void
    @State private var hoveredArtist: String?

    var body: some View {
        List(artists) { artist in
            HStack {
                Button { onOpen(artist) } label: {
                    HStack(spacing: 12) {
                        ArtworkView(track: artist.representative)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(artist.id).font(.headline)
                            Text("\(artist.count) 首歌曲").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4).padding(.horizontal, 6)
                    .background(hoveredArtist == artist.id ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredArtist = $0 ? artist.id : nil }
                .help("查看「\(artist.id)」的歌曲")
                .accessibilityLabel("\(artist.id)，\(artist.count) 首歌曲")
            }
        }
    }
}

#Preview {
    ArtistsView(artists: LibraryViewModel.preview(section: .artists).result.artists, onOpen: { _ in })
        .frame(width: 650, height: 400)
}
