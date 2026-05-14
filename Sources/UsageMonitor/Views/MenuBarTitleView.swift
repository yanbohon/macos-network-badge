import SwiftUI

struct MenuBarTitleView: View {
    static let menuBarTitleWidth: CGFloat = 82
    private static let statusSquare = "■"

    let text: String
    let color: Color
    let statusCells: [ServiceStatusDisplayCell]
    let statusCellsAreStale: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(Self.statusSymbolText(for: statusCells))
                .foregroundColor(Self.latestStatusKind(for: statusCells).swiftUIColor)
            Text(text)
                .foregroundColor(color)
        }
        .font(.system(size: 13, weight: .medium))
        .monospacedDigit()
        .frame(width: Self.menuBarTitleWidth, alignment: .center)
        .fixedSize(horizontal: true, vertical: true)
    }

    static func combinedText(text: String, statusCells: [ServiceStatusDisplayCell]) -> String {
        "\(statusSymbolText(for: statusCells)) \(text)"
    }

    static func statusSymbolText(for cells: [ServiceStatusDisplayCell]) -> String {
        statusSquare
    }

    static func latestStatusKind(for cells: [ServiceStatusDisplayCell]) -> ServiceStatusCellKind {
        cells.last?.kind ?? .gray
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
}
