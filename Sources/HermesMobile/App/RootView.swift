import SwiftUI

/// Top-level entry. Wire this into your iOS app target via:
///
/// ```swift
/// @main
/// struct HermesMobileApp: App {
///     var body: some Scene {
///         WindowGroup { HermesMobile.RootView() }
///     }
/// }
/// ```
public struct RootView: View {
    @State private var appState: AppState

    public init(appState: AppState = AppState()) {
        _appState = State(initialValue: appState)
    }

    public var body: some View {
        Group {
            switch appState.screen {
            case .setup:
                SetupView(viewModel: SetupViewModel(onCompleted: { client in
                    appState.handleSetupCompleted(client)
                }))
            case .main:
                MainShell(appState: appState)
            }
        }
        .task {
            appState.boot()
        }
        .privacyShield()
        .onChange(of: appState.activeSessionId) { _, _ in
            appState.persistActiveSession()
        }
    }
}

private struct MainShell: View {
    @Bindable var appState: AppState
    @State private var showSettings: Bool = false

    var body: some View {
        NavigationSplitView {
            if let api = appState.apiClient {
                SessionListContainer(api: api, appState: appState) {
                    showSettings = true
                }
            } else {
                ProgressView()
            }
        } detail: {
            chatDetail
        }
        .sheet(isPresented: $showSettings) {
            if appState.apiClient != nil {
                SettingsView(viewModel: SettingsViewModel(onSignOut: {
                    appState.signOut()
                }))
            }
        }
    }

    @ViewBuilder
    private var chatDetail: some View {
        if let sessionId = appState.activeSessionId,
           let chatVM = appState.chatViewModel(for: sessionId) {
            ChatView(viewModel: chatVM)
                .id(sessionId)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("選擇或新建一個 session")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionListContainer: View {
    @State private var viewModel: SessionListViewModel
    private let onSettings: () -> Void

    init(api: APIClientProtocol, appState: AppState, onSettings: @escaping () -> Void) {
        _viewModel = State(initialValue: SessionListViewModel(api: api, appState: appState))
        self.onSettings = onSettings
    }

    var body: some View {
        SessionListView(viewModel: viewModel, onSettingsTap: onSettings)
    }
}

#Preview {
    RootView()
}
