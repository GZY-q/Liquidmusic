import SwiftUI

struct AlbumHeaderView: View {
    let album: AlbumIdentity
    let paths: [String]
    var loadArtwork: ArtworkDataLoader = ArtworkLoadingState.cachedData

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ArtworkView(paths: paths, size: 80, loadArtwork: loadArtwork)
            VStack(alignment: .leading, spacing: 6) {
                Text(album.title).font(.title2).lineLimit(2)
                Text(album.artist).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

#Preview("专辑页头·窄窗") {
    AlbumHeaderView(album: AlbumIdentity(SPXData.tracks[0]), paths: [])
        .frame(width: 320)
}
