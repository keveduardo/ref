import RefKit
import SwiftUI

/// RefKit carries team colours as tokens (it has no SwiftUI); the watch maps
/// them here.
extension TeamColor {
    var watchColor: Color {
        switch self {
        case .red: .red
        case .blue: .blue
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .purple: .purple
        case .black: .primary
        case .white: .white
        }
    }
}
