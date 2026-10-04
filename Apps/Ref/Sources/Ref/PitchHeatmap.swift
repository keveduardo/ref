import RefKit
import SwiftUI

/// The pitch diagram: the field to scale, its markings, and where the
/// referee spent the match — cool to hot. Drawn lengthways, with the goal the
/// referee faced when marking the field on the right.
struct PitchHeatmap: View {
    let report: MovementReport
    let size: PitchSize

    var body: some View {
        Canvas { context, canvas in
            let scale = min(canvas.width / size.length, canvas.height / size.width)
            let field = CGRect(x: (canvas.width - size.length * scale) / 2,
                               y: (canvas.height - size.width * scale) / 2,
                               width: size.length * scale, height: size.width * scale)
            context.fill(Path(field), with: .color(Color(red: 0.16, green: 0.45, blue: 0.24)))

            // Heat, under the lines. Rows run from the right touchline (as the
            // referee faced) to the left, so row 0 is drawn at the bottom.
            let hottest = max(report.hottest, 1)
            let cellW = field.width / CGFloat(report.columns)
            let cellH = field.height / CGFloat(report.rows)
            for row in 0..<report.rows {
                for column in 0..<report.columns {
                    let seconds = report.heat[row * report.columns + column]
                    guard seconds > 0 else { continue }
                    let level = (seconds / hottest).squareRoot()  // so the warm edges show
                    let cell = CGRect(x: field.minX + CGFloat(column) * cellW,
                                      y: field.maxY - CGFloat(row + 1) * cellH,
                                      width: cellW + 0.5, height: cellH + 0.5)
                    context.fill(Path(cell), with: .color(heatColor(level).opacity(0.25 + 0.6 * level)))
                }
            }

            // Markings.
            var lines = Path()
            lines.addRect(field)
            lines.move(to: CGPoint(x: field.midX, y: field.minY))
            lines.addLine(to: CGPoint(x: field.midX, y: field.maxY))
            let radius = min(9.15, size.width * 0.13) * scale
            lines.addEllipse(in: CGRect(x: field.midX - radius, y: field.midY - radius,
                                        width: radius * 2, height: radius * 2))
            let depth = size.penaltyDepth * scale, wide = size.penaltyWidth * scale
            lines.addRect(CGRect(x: field.minX, y: field.midY - wide / 2, width: depth, height: wide))
            lines.addRect(CGRect(x: field.maxX - depth, y: field.midY - wide / 2, width: depth, height: wide))
            context.stroke(lines, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
        }
        .aspectRatio(size.length / size.width, contentMode: .fit)
        .accessibilityLabel("Heatmap of where you moved on the field")
    }

    /// Blue through yellow to red.
    private func heatColor(_ level: Double) -> Color {
        level < 0.5
            ? Color(red: level * 2, green: level * 2, blue: 1 - level * 2)
            : Color(red: 1, green: 2 - level * 2, blue: 0)
    }
}
