import SwiftUI

public struct SessionListView: View {
    @Bindable private var viewModel: SessionListViewModel
    @State private var renameTarget: SessionListItem?
    @State private var renameText: String = ""
    @State private var showSettings: Bool = false

    private let onSettingsTap: () -> Void

    public init(viewModel: SessionListViewModel, onSettingsTap: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onSettingsTap = onSettingsTap
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.sessions.isEmpty {
                ProgressView("載入 session…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.sessions.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.createNew() }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(viewModel.pendingNewSession)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onSettingsTap()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        .alert("錯誤", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .sheet(item: $renameTarget) { item in
            renameSheet(for: item)
        }
    }

    private var listContent: some View {
        List {
            ForEach(viewModel.sessions) { item in
                Button {
                    viewModel.select(item.sessionId)
                } label: {
                    SessionRowView(session: item)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await viewModel.delete(item.sessionId) }
                    } label: {
                        Label("刪除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        renameTarget = item
                        renameText = item.title
                    } label: {
                        Label("更名", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("還沒有 session")
                .font(.headline)
            Text("點選右上「+」開啟一個新的對話。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                Task { await viewModel.createNew() }
            } label: {
                Label("New session", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.pendingNewSession)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func renameSheet(for item: SessionListItem) -> some View {
        NavigationStack {
            Form {
                TextField("名稱", text: $renameText)
            }
            .navigationTitle("重新命名")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { renameTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        Task {
                            await viewModel.rename(item.sessionId, to: renameText)
                            renameTarget = nil
                        }
                    }
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
