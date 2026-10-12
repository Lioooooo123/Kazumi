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
                    Label("下载", systemImage: "arrow.down.circle").tag(SidebarItem.downloads)
                }
                Section {
                    Label("规则", systemImage: "puzzlepiece.extension").tag(SidebarItem.rules)
                    Label("设置", systemImage: "gearshape").tag(SidebarItem.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 208, max: 260)
            .navigationTitle("小栗子")
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
            .background(KazumiTheme.canvas(scheme, oled: model.settings.oled))
        }
        .background(KazumiTheme.canvas(scheme, oled: model.settings.oled))
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("搜索", systemImage: "magnifyingglass") { model.sidebar = .search }
                    .help("搜索")
                    .accessibilityLabel("搜索")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !model.notice.isEmpty {
                Text(model.notice)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
                    .accessibilityLabel(model.notice)
            }
        }
        .onChange(of: model.notice) { _, value in
            guard !value.isEmpty else { return }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if model.notice == value { model.notice = "" }
            }
        }
        .sheet(isPresented: Binding(
            get: { !model.captchaURL.isEmpty },
            set: { if !$0 { model.captchaURL = "" } }
        )) {
            if let url = URL(string: model.captchaURL) {
                CaptchaSheet(url: url) { header in
                    model.ruleCookies[model.captchaPlugin] = header
                    model.captchaURL = ""
                    model.postNotice("已保存验证 Cookie，可以重新搜索")
                }
            }
        }
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
        .animation(.easeInOut(duration: 0.2), value: model.nowPlaying?.pageURL)
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
        case .downloads: DownloadsView()
        case .rules: RulesView()
        case .settings: SettingsView()
        }
    }
}
