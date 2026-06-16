import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: AppStore
    @State private var searchText = ""
    @State private var selectedGame: GameInfo?

    var filtered: [GameInfo] {
        if searchText.isEmpty { return store.games }
        return store.games.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if store.games.isEmpty {
                emptyState
            } else {
                gameGrid
            }
        }
        .navigationTitle("Game Library")
        .searchable(text: $searchText, prompt: "Search games")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await store.launchSteam()
                    }
                } label: {
                    Label("Open Steam", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            ToolbarItem {
                Button {
                    Task { await store.refreshLibrary() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .overlay {
            if store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 72))
                .foregroundStyle(.tertiary)

            Text("No games found")
                .font(.title2.bold())

            Text("Install games via Steam, then refresh.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Open Steam") {
                    Task { await store.launchSteam() }
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh") {
                    Task { await store.refreshLibrary() }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gameGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 200))],
                spacing: 16
            ) {
                ForEach(filtered) { game in
                    GameCard(game: game)
                        .onTapGesture {
                            Task { await store.launch(game: game) }
                        }
                }
            }
            .padding()
        }
    }
}

struct GameCard: View {
    let game: GameInfo
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Game art (fetched from Steam CDN)
            AsyncImage(url: steamArtURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.2))
                        .overlay(
                            Image(systemName: "gamecontroller")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        )
                @unknown default:
                    ProgressView()
                }
            }
            .frame(height: 120)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("App \(game.appId)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.background)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(hovered ? 0.25 : 0.12),
                radius: hovered ? 8 : 4, y: hovered ? 4 : 2)
        .scaleEffect(hovered ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .onHover { hovered = $0 }
    }

    private var steamArtURL: URL? {
        URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(game.appId)/header.jpg")
    }
}
