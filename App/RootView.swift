// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var navigationPaths: [SidebarItem: NavigationPath] = [:]

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("浏览") {
                    Label("推荐", systemImage: "house").tag(SidebarItem.popular)
                    Label("时间表", systemImage: "calendar").tag(SidebarItem.timeline)
                    Label("搜索", systemImage: "magnifyingglass").tag(SidebarItem.search)
                }
                Section("资料库") {
                    Label("追番", systemImage: "heart").tag(SidebarItem.favorites)
                    Label("历史", systemImage: "clock.arrow.circlepath").tag(SidebarItem.history)
                    Group {
                        if activeDownloads > 0 {
                            Label("下载", systemImage: "arrow.down.circle").badge(activeDownloads)
                        } else {
                            Label("下载", systemImage: "arrow.down.circle")
                        }
                    }
                    .tag(SidebarItem.downloads)
                    .accessibilityLabel(activeDownloads > 0 ? "下载，\(activeDownloads) 个进行中" : "下载")
                }
                Section {
                    Label("规则", systemImage: "puzzlepiece.extension").tag(SidebarItem.rules)
                    SettingsLink { Label("设置…", systemImage: "gearshape") }
                        .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 208, max: 260)
            .navigationTitle("小栗子")
        } detail: {
            NavigationStack(path: $model.path) {
                detail(for: model.sidebar)
                    .id(model.sidebar)
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
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                    Text(model.notice)
                        .font(.callout)
                        .textSelection(.enabled)
                    Button {
                        model.notice = ""
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("关闭提示")
                    .accessibilityLabel("关闭提示")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8)
                .accessibilityElement(children: .contain)
            }
        }
        .onChange(of: model.notice) { _, value in
            guard !value.isEmpty else { return }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if model.notice == value { model.notice = "" }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { !model.captchaURL.isEmpty },
                set: { if !$0 { model.captchaURL = "" } }
            )
        ) {
            if let url = URL(string: model.captchaURL) {
                CaptchaSheet(url: url) { header in
                    model.ruleCookies[model.captchaPlugin] = header
                    model.captchaURL = ""
                    model.postNotice("已保存验证 Cookie，可以重新搜索")
                }
            }
        }
        .onChange(of: model.sidebar) { previous, selected in
            navigationPaths[previous] = model.path
            model.path = navigationPaths[selected] ?? NavigationPath()
        }
        .disabled(model.nowPlaying != nil)
        .accessibilityHidden(model.nowPlaying != nil)
        .overlay {
            if let request = model.nowPlaying {
                GeometryReader { geometry in
                    PlayerScreen(request: request)
                        .id(request.pageURL)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
    }

    private var activeDownloads: Int {
        model.downloads.filter { $0.status == "running" || $0.status == "queued" }.count
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
        case .settings:
            EmptyHint(title: "应用设置", message: "在独立窗口中调整外观、播放和同步。", systemImage: "gearshape")
                .overlay(alignment: .bottom) { SettingsLink { Text("打开设置…") }.padding(24) }
        }
    }
}
