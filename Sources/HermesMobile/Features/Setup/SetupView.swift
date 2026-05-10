import SwiftUI

public struct SetupView: View {
    @Bindable private var viewModel: SetupViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case url
        case password
    }

    public init(viewModel: SetupViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("http://100.x.x.x:8787", text: $viewModel.serverURLText)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .url)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }

                Section("密碼") {
                    SecureField("HERMES_WEBUI_PASSWORD", text: $viewModel.passwordText)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await viewModel.save() } }
                }

                Section {
                    Button {
                        Task { await viewModel.testConnection() }
                    } label: {
                        HStack {
                            Text("測試連線")
                            Spacer()
                            statusIndicator
                        }
                    }
                    .disabled(!viewModel.canSubmit || viewModel.testStatus == .testing)

                    if let detail = statusDetail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(statusColor)
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("HermesMobile 設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        Task { await viewModel.save() }
                    }
                    .disabled(!viewModel.canSubmit || viewModel.isSaving)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch viewModel.testStatus {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private var statusDetail: String? {
        switch viewModel.testStatus {
        case .idle, .testing:
            return nil
        case let .success(sessions, version):
            if let version {
                return "連線成功（\(sessions) sessions, server v\(version)）"
            }
            return "連線成功（\(sessions) sessions）"
        case let .failure(message):
            return message
        }
    }

    private var statusColor: Color {
        switch viewModel.testStatus {
        case .success: return .green
        case .failure: return .red
        default: return .secondary
        }
    }
}

#Preview {
    SetupView(
        viewModel: SetupViewModel(
            preferences: Preferences(defaults: UserDefaults(suiteName: "preview")!),
            secrets: InMemorySecretStore(),
            onCompleted: { _ in }
        )
    )
}
