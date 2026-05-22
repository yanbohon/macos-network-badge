import SwiftUI

struct MenuBarKeyDisplayRow: Equatable, Identifiable {
    let id: String
    let name: String
    let symbolName: String
    let text: String
}

struct MenuBarTitleView: View {
    static let statusCellSize = CGSize(width: 4, height: 4)
    static let statusCellSpacing: CGFloat = 1.5
    static let topSectionRatio: CGFloat = 0.25

    let text: String
    let color: Color
    let statusCells: [ServiceStatusDisplayCell]
    let statusCellsAreStale: Bool
    let keyRows: [MenuBarKeyDisplayRow]

    init(
        text: String,
        color: Color,
        statusCells: [ServiceStatusDisplayCell],
        statusCellsAreStale: Bool,
        keyRows: [MenuBarKeyDisplayRow] = []
    ) {
        self.text = text
        self.color = color
        self.statusCells = statusCells
        self.statusCellsAreStale = statusCellsAreStale
        self.keyRows = keyRows
    }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: Self.statusCellSpacing) {
                ForEach(Array(statusCells.enumerated()), id: \.offset) { _, cell in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(cell.kind.swiftUIColor)
                        .frame(width: Self.statusCellSize.width, height: Self.statusCellSize.height)
                        .opacity(cell.kind == .gray ? 0.45 : 1)
                }
            }
            .opacity(statusCellsAreStale ? 0.55 : 1)

            Text(text)
                .foregroundColor(color)
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .center)
        .fixedSize(horizontal: true, vertical: true)
    }

    static func normalizedStatusCells(
        for cells: [ServiceStatusDisplayCell],
        count: Int
    ) -> [ServiceStatusDisplayCell] {
        let recentCells = Array(cells.suffix(count))
        let missingCount = max(0, count - recentCells.count)
        let missingCells = Array(repeating: ServiceStatusDisplayCell(kind: .gray, probe: nil), count: missingCount)
        return missingCells + recentCells
    }

    static func latestStatusKind(for cells: [ServiceStatusDisplayCell], count: Int) -> ServiceStatusCellKind {
        normalizedStatusCells(for: cells, count: count).last?.kind ?? .gray
    }

    static func accessibilityTitle(text: String, statusCells: [ServiceStatusDisplayCell], count: Int) -> String {
        "\(latestStatusKind(for: statusCells, count: count).accessibilityTitle) \(text)"
    }

    static func accessibilityTitle(
        keyRows: [MenuBarKeyDisplayRow],
        statusCells: [ServiceStatusDisplayCell],
        statusCellsAreStale: Bool
    ) -> String {
        let statusText = latestStatusKind(for: statusCells, count: 2).accessibilityTitle
            + (statusCellsAreStale ? "（缓存）" : "")
        let keyText = keyRows
            .map { "\($0.name) \($0.text)" }
            .joined(separator: "，")
        return keyText.isEmpty ? statusText : "\(statusText) \(keyText)"
    }

    static func keyGridColumnCount(forKeyCount keyCount: Int) -> Int {
        max(1, Int(ceil(Double(max(1, keyCount)) / 2.0)))
    }

    static func keyGridColumns(for rows: [MenuBarKeyDisplayRow]) -> [[MenuBarKeyDisplayRow]] {
        guard !rows.isEmpty else { return [[]] }
        return stride(from: 0, to: rows.count, by: 2).map { start in
            Array(rows[start..<min(start + 2, rows.count)])
        }
    }

    static func resolvedSymbolName(_ symbolName: String) -> String {
        let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        #if os(macOS)
        if !trimmed.isEmpty, NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil {
            return trimmed
        }
        #endif
        return UsageKeyConfiguration.defaultSymbolName
    }
}

extension ServiceStatusCellKind {
    var swiftUIColor: Color {
        switch self {
        case .green:
            return .green
        case .yellow:
            return .yellow
        case .red:
            return .red
        case .gray:
            return .secondary
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .green:
            return "服务状态正常"
        case .yellow:
            return "服务状态高延迟"
        case .red:
            return "服务状态失败"
        case .gray:
            return "服务状态未知"
        }
    }
}
