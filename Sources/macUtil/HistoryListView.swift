import ClipboardKit
import SwiftUI

struct HistoryListView: View {
    @Bindable var viewModel: HistoryViewModel
    let onPick: (ClipItem) -> Void
    let onDismiss: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Buscar no histórico", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(10)
                .focused($searchFocused)
                .onSubmit { pickSelected() }

            Divider()

            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    viewModel.query.isEmpty ? "Histórico vazio" : "Nada encontrado",
                    systemImage: "list.clipboard"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { scroll in
                    List(viewModel.items, selection: $viewModel.selection) { item in
                        row(for: item)
                            .id(item.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: viewModel.selection) { _, new in
                        guard let new else { return }
                        withAnimation(.none) { scroll.scrollTo(new) }
                    }
                }
            }

            Divider()

            Text("↑↓ navegar · ⏎ usar · ⌫ apagar · esc fechar")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
        .frame(width: 440, height: 420)
        .onAppear { searchFocused = true }
        .onKeyPress(.downArrow) { viewModel.moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { viewModel.moveSelection(by: -1); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onKeyPress(.return) { pickSelected(); return .handled }
        .onKeyPress(.delete) { deleteSelected(); return .handled }
    }

    private func row(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.preview)
                .lineLimit(1)
            Text(item.copiedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onPick(item) }
    }

    private func pickSelected() {
        guard let item = viewModel.selectedItem else { return }
        onPick(item)
    }

    private func deleteSelected() {
        guard let id = viewModel.selection else { return }
        viewModel.delete(id: id)
    }
}
