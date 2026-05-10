import SwiftUI

public struct SettingsView: View {
    @Bindable private var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("URL", value: viewModel.serverDisplayURL)
                    LabeledContent("密碼", value: viewModel.hasStoredPassword ? "已儲存於 Keychain" : "未儲存")
                }

                Section {
                    Button(role: .destructive) {
                        viewModel.signOut()
                        dismiss()
                    } label: {
                        Label("登出並清除設定", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text("會清除 Keychain 內的密碼與 cookie，並刪除儲存的 server URL 與 last session。")
                }

                Section("關於") {
                    LabeledContent("App", value: "HermesMobile")
                    LabeledContent("版本", value: Self.bundleVersion)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private static var bundleVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
