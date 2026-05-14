import SwiftUI

struct MenuBarTitleView: View {
    static let statusCellSize = CGSize(width: 4, height: 4)
    static let statusCellSpacing: CGFloat = 1.5
    static let topSectionRatio: CGFloat = 0.25

    let text: String
    let color: Color
    let statusCells: [ServiceStatusDisplayCell]
    let statusCellsAreStale: Bool

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
