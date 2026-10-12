// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("浏览") {
                    Label("推荐", systemImage: "house").tag(SidebarItem.popular)
                    Label("时间表", systemImage: "calendar").tag(SidebarItem.timeline)
                    Label("搜索", systemImage: "magnifyingglass").tag(SidebarItem.search)
                }
                Section("收藏") {
                    Label("追番", systemImage: "heart").tag(SidebarItem.favorites)
                    Label("历史", systemImage: "clock.arrow.circlepath").tag(SidebarItem.history)
                }
                Section {
                    Label("规则", systemImage: "puzzlepiece.extension").tag(SidebarItem.rules)
                    Label("设置", systemImage: "gearshape").tag(SidebarItem.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 208, max: 260)
            .navigationTitle("Kazumi")
        } detail: {
            NavigationStack(path: $model.path) {
                detail(for: model.sidebar)
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .detail(let id):
                            DetailView(subjectID: id)
                        case .episodes(let route):
                            EpisodesView(route: route)
                        }
                    }
            }
            .background(KazumiTheme.canvas(scheme))
        }
        .background(KazumiTheme.canvas(scheme))
        .onChange(of: model.sidebar) { _, _ in
            model.path = NavigationPath()
        }
        .overlay {
            if let request = model.nowPlaying {
                PlayerScreen(request: request)
                    .id(request.pageURL)
                    .transition(.opacity)
            }
        }
    }

    /// `List` selection is optional. Clearing the highlight should not leave the detail blank.
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { model.sidebar },
            set: { newValue in
                if let newValue { model.sidebar = newValue }
            }
        )
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .popular: PopularView()
        case .timeline: SeasonCalendarView()
        case .search: SearchView()
        case .favorites: FavoritesView()
        case .history: HistoryView()
        case .rules: RulesView()
        case .settings: SettingsView()
        }
    }
}
