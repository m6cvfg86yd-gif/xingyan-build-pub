import SwiftUI

struct OrbitTabGlyph: View {
    let kind: Int
    let selected: Bool
    let color: Color
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            context.scaleBy(x: side / 24, y: side / 24)
            let line = StrokeStyle(
                lineWidth: selected ? 1.9 : 1.65,
                lineCap: .round,
                lineJoin: .round
            )
            let fine = StrokeStyle(
                lineWidth: selected ? 1.25 : 1.05,
                lineCap: .round,
                lineJoin: .round
            )

            switch kind {
            case 0:
                drawConversation(context, line: line, fine: fine)
            case 1:
                drawContacts(context, line: line, fine: fine)
            case 2:
                drawWorld(context, line: line, fine: fine)
            default:
                drawProfile(context, line: line, fine: fine)
            }
        }
        .frame(width: 24, height: 24)
    }

    private func drawConversation(_ context: GraphicsContext,
                                  line: StrokeStyle, fine: StrokeStyle) {
        var orbit = Path()
        orbit.addArc(center: CGPoint(x: 12, y: 12), radius: 10.2,
                     startAngle: .degrees(-72), endAngle: .degrees(206),
                     clockwise: false)
        context.stroke(orbit, with: .color(accent.opacity(selected ? 0.62 : 0.38)),
                       style: fine)

        var bubble = Path(roundedRect: CGRect(x: 4.4, y: 5.8, width: 15.2, height: 11.2),
                          cornerRadius: 4.6)
        bubble.move(to: CGPoint(x: 8.6, y: 16.6))
        bubble.addLine(to: CGPoint(x: 7.8, y: 20.1))
        bubble.addLine(to: CGPoint(x: 12.5, y: 17.1))
        if selected {
            context.fill(bubble, with: .color(color.opacity(0.18)))
        }
        context.stroke(bubble, with: .color(color), style: line)
        context.fill(Path(ellipseIn: CGRect(x: 18.2, y: 3.8, width: 3.1, height: 3.1)),
                     with: .color(accent))
    }

    private func drawContacts(_ context: GraphicsContext,
                              line: StrokeStyle, fine: StrokeStyle) {
        let nodes = [
            CGPoint(x: 6.4, y: 9.2),
            CGPoint(x: 17.4, y: 7.8),
            CGPoint(x: 12.2, y: 18.0)
        ]

        var links = Path()
        links.move(to: nodes[0])
        links.addCurve(to: nodes[1],
                       control1: CGPoint(x: 9.2, y: 4.8),
                       control2: CGPoint(x: 14.4, y: 4.5))
        links.move(to: nodes[0])
        links.addCurve(to: nodes[2],
                       control1: CGPoint(x: 6.3, y: 14.2),
                       control2: CGPoint(x: 9.2, y: 17.5))
        links.move(to: nodes[1])
        links.addCurve(to: nodes[2],
                       control1: CGPoint(x: 17.0, y: 12.9),
                       control2: CGPoint(x: 14.7, y: 17.2))
        context.stroke(links, with: .color(accent.opacity(selected ? 0.62 : 0.40)),
                       style: fine)

        for (index, point) in nodes.enumerated() {
            let radius: CGFloat = index == 2 ? 2.8 : 2.5
            let rect = CGRect(x: point.x - radius, y: point.y - radius,
                              width: radius * 2, height: radius * 2)
            let circle = Path(ellipseIn: rect)
            if selected && index == 2 {
                context.fill(circle, with: .color(color.opacity(0.24)))
            }
            context.stroke(circle, with: .color(color), style: line)
        }
    }

    private func drawWorld(_ context: GraphicsContext,
                           line: StrokeStyle, fine: StrokeStyle) {
        let globe = Path(ellipseIn: CGRect(x: 4.1, y: 4.1, width: 15.8, height: 15.8))
        if selected {
            context.fill(globe, with: .color(color.opacity(0.14)))
        }
        context.stroke(globe, with: .color(color), style: line)

        var meridian = Path()
        meridian.addEllipse(in: CGRect(x: 8.2, y: 4.2, width: 7.6, height: 15.6))
        context.stroke(meridian, with: .color(color.opacity(0.58)), style: fine)

        context.drawLayer { layer in
            layer.translateBy(x: 12, y: 12)
            layer.rotate(by: .degrees(-27))
            let ring = Path(ellipseIn: CGRect(x: -10.7, y: -4.8, width: 21.4, height: 9.6))
            layer.stroke(ring, with: .color(accent.opacity(selected ? 0.72 : 0.45)),
                         style: fine)
        }
        context.fill(Path(ellipseIn: CGRect(x: 19.3, y: 4.4, width: 3.0, height: 3.0)),
                     with: .color(accent))
    }

    private func drawProfile(_ context: GraphicsContext,
                             line: StrokeStyle, fine: StrokeStyle) {
        var orbit = Path()
        orbit.addArc(center: CGPoint(x: 12, y: 12), radius: 10.2,
                     startAngle: .degrees(198), endAngle: .degrees(474),
                     clockwise: false)
        context.stroke(orbit, with: .color(accent.opacity(selected ? 0.64 : 0.38)),
                       style: fine)

        let head = Path(ellipseIn: CGRect(x: 8.7, y: 5.5, width: 6.6, height: 6.6))
        if selected {
            context.fill(head, with: .color(color.opacity(0.22)))
        }
        context.stroke(head, with: .color(color), style: line)

        var shoulders = Path()
        shoulders.move(to: CGPoint(x: 5.7, y: 20.2))
        shoulders.addCurve(to: CGPoint(x: 18.3, y: 20.2),
                           control1: CGPoint(x: 6.8, y: 14.6),
                           control2: CGPoint(x: 17.2, y: 14.6))
        context.stroke(shoulders, with: .color(color), style: line)
        context.fill(Path(ellipseIn: CGRect(x: 20.0, y: 5.1, width: 2.8, height: 2.8)),
                     with: .color(accent))
    }
}
