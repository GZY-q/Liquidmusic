import SwiftUI

struct AlbumsView: View {
    let albums: [LibraryAlbum]
    let onOpen: (LibraryAlbum) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .top)], alignment: .leading, spacing: 24) {
                ForEach(albums) { album in
                    AlbumButton(album: album) { onOpen(album) }
                }
            }.padding(20)
        }
    }
}

private struct AlbumButton: View {
    let album: LibraryAlbum
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkView(track: album.representative, size: 144)
                Text(album.id.title).font(.headline).lineLimit(2)
                Text(album.id.artist).foregroundStyle(.secondary).lineLimit(1)
                Text("\(album.count) 首歌曲").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("查看「\(album.id.title)」的歌曲")
        .accessibilityLabel("\(album.id.title)，\(album.id.artist)，\(album.count) 首歌曲")
    }
}

#Preview {
    AlbumsView(albums: LibraryViewModel.preview(section: .albums).result.albums, onOpen: { _ in })
        .frame(width: 760, height: 440)
}
