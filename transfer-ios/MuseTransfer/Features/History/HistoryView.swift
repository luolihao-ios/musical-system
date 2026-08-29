import SwiftUI

struct HistoryView: View {
    @Bindable var model: TransferModel
    var body: some View {
        NavigationStack {
            List(model.history) { item in
                VStack(alignment: .leading, spacing: 4) { Text(item.deviceName).font(.headline); Text(item.fileNames.joined(separator: "、")).lineLimit(2); Text(item.date, style: .date).font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("历史").toolbar { Button("清除", role: .destructive, action: model.clearHistory) }
        }
    }
}
