import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var engine: WineEngine
    @State private var games: [GameEntry] = []
    @State private var search = ""

    var filtered: [GameEntry] { search.isEmpty ? games : games.filter { $0.name.localizedCaseInsensitiveContains(search) } }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if games.isEmpty { emptyState } else { grid }
        }
        .searchable(text: $search)
        .onAppear { games = engine.scanGames() }
        .alert("Error", isPresented: .constant(isError)) {
            Button("OK") { engine.stage = .idle }
        } message: { if case .error(let m) = engine.stage { Text(m) } }
    }

    private var isError: Bool { if case .error = engine.stage { return true }; return false }

    private var sidebar: some View {
        List {
            Section("Steam") {
                Button { engine.launchSteam() } label: { Label("Open Steam", systemImage: "play.fill") }.buttonStyle(.plain)
                Button { games = engine.scanGames() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.plain)
            }
            Section("Folders") {
                Button { engine.openFolder(WsteamPaths.steamapps ?? WsteamPaths.base) } label: { Label("Games / Mods", systemImage: "folder.badge.gearshape") }.buttonStyle(.plain)
                Button { engine.openFolder(WsteamPaths.cxSteamBottle?.url.appendingPathComponent("drive_c") ?? WsteamPaths.base) } label: { Label("Wine C:\\", systemImage: "internaldrive") }.buttonStyle(.plain)
            }
            Section("System") {
                Button { engine.stage = .idle } label: { Label("Setup", systemImage: "gearshape") }.buttonStyle(.plain)
                Button { engine.killWineserver() } label: { Label("Kill Wineserver", systemImage: "xmark.octagon") }.buttonStyle(.plain).foregroundStyle(.red)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 190)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 195))], spacing: 14) {
                ForEach(filtered) { game in
                    GameCard(game: game)
                        .onTapGesture { engine.launchGame(appId: game.appId) }
                        .contextMenu {
                            Button { engine.launchGame(appId: game.appId) } label: { Label("Play", systemImage: "play.fill") }
                            Divider()
                            Button { engine.openFolder(game.installDir) } label: { Label("Open in Finder", systemImage: "folder") }
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(game.installDir.path, forType: .string)
                            } label: { Label("Copy Path", systemImage: "doc.on.clipboard") }
                        }
                }
            }.padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller").font(.system(size: 60)).foregroundStyle(.tertiary)
            Text("No games found").font(.title2.bold())
            Text("Log into Steam and install games, then refresh.").foregroundStyle(.secondary)
            Button("Open Steam") { engine.launchSteam() }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GameCard: View {
    let game: GameEntry
    @State private var hovered = false
    var body: some View {
        VStack(spacing: 0) {
            AsyncImage(url: URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(game.appId)/header.jpg")) { phase in
                if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                else { Rectangle().fill(Color.blue.opacity(0.15)).overlay(Image(systemName: "gamecontroller").foregroundStyle(.secondary)) }
            }.frame(height: 110).clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name).font(.caption.bold()).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Text("App \(game.appId)").font(.caption2).foregroundStyle(.secondary)
            }.padding(8).background(.background)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .shadow(color: .black.opacity(hovered ? 0.22 : 0.1), radius: hovered ? 8 : 4, y: hovered ? 3 : 1)
        .scaleEffect(hovered ? 1.03 : 1).animation(.easeInOut(duration: 0.13), value: hovered)
        .onHover { hovered = $0 }
    }
}
