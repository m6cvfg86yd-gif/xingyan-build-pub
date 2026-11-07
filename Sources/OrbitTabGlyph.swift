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
                drawStar(context, line: line, fine: fine)
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

    private func drawStar(_ context: GraphicsContext,
                          line: StrokeStyle, fine: StrokeStyle) {
        var star = Path()
        star.move(to: CGPoint(x: 12, y: 1.8))
        star.addCurve(to: CGPoint(x: 21.9, y: 12),
                      control1: CGPoint(x: 12.6, y: 7.2),
                      control2: CGPoint(x: 16.8, y: 11.4))
        star.addCurve(to: CGPoint(x: 12, y: 22.2),
                      control1: CGPoint(x: 16.8, y: 12.6),
                      control2: CGPoint(x: 12.6, y: 16.8))
        star.addCurve(to: CGPoint(x: 2.1, y: 12),
                      control1: CGPoint(x: 7.2, y: 16.8),
                      control2: CGPoint(x: 11.4, y: 12.6))
        star.addCurve(to: CGPoint(x: 12, y: 1.8),
                      control1: CGPoint(x: 11.4, y: 7.2),
                      control2: CGPoint(x: 7.2, y: 11.4))
        star.closeSubpath()
        if selected {
            context.fill(
                star,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: color.opacity(0.52), location: 0),
                        .init(color: Color(hex: 0xA7D96A).opacity(0.34), location: 0.72),
                        .init(color: Color(hex: 0xD9B95F).opacity(0.20), location: 1)
                    ]),
                    startPoint: CGPoint(x: 4, y: 4),
                    endPoint: CGPoint(x: 20, y: 20)
                )
            )
        }
        context.stroke(star, with: .color(color), style: line)

        if selected {
            var eyes = Path()
            eyes.move(to: CGPoint(x: 10.85, y: 11.8))
            eyes.addLine(to: CGPoint(x: 10.85, y: 13.05))
            eyes.move(to: CGPoint(x: 13.15, y: 11.8))
            eyes.addLine(to: CGPoint(x: 13.15, y: 13.05))
            context.stroke(eyes, with: .color(color.opacity(0.86)), style: fine)
        }

        context.fill(Path(ellipseIn: CGRect(x: 20.2, y: 2.8, width: 2.2, height: 2.2)),
                     with: .color(accent.opacity(selected ? 0.90 : 0.58)))
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
        let planetRect = CGRect(x: 5.4, y: 5.2, width: 13.2, height: 13.2)
        let planet = Path(ellipseIn: planetRect)
        if selected {
            context.fill(
                planet,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: color.opacity(0.44), location: 0),
                        .init(color: Color(hex: 0xA7D96A).opacity(0.28), location: 0.72),
                        .init(color: Color(hex: 0xD9B95F).opacity(0.16), location: 1)
                    ]),
                    startPoint: CGPoint(x: 6, y: 5.5),
                    endPoint: CGPoint(x: 18, y: 18.5)
                )
            )
        }
        context.stroke(planet, with: .color(color), style: line)

        context.drawLayer { layer in
            layer.clip(to: planet)
            let shade = Path(ellipseIn: CGRect(x: 8.5, y: 4.7, width: 11.1, height: 14.7))
            layer.stroke(shade, with: .color(color.opacity(0.46)), style: fine)
        }

        context.drawLayer { layer in
            layer.translateBy(x: 12, y: 12)
            layer.rotate(by: .degrees(-24))
            let ring = Path(ellipseIn: CGRect(x: -11.3, y: -4.1, width: 22.6, height: 8.2))
            if selected {
                layer.fill(
                    ring,
                    with: .linearGradient(
                        Gradient(colors: [
                            color.opacity(0.20),
                            Color(hex: 0xA7D96A).opacity(0.12),
                            Color(hex: 0xD9B95F).opacity(0.06)
                        ]),
                        startPoint: CGPoint(x: -11, y: 0),
                        endPoint: CGPoint(x: 11, y: 0)
                    )
                )
            }
            layer.stroke(ring, with: selected
                         ? .linearGradient(
                            Gradient(colors: [
                                color.opacity(0.92),
                                Color(hex: 0xA7D96A),
                                Color(hex: 0xD9B95F)
                            ]),
                            startPoint: CGPoint(x: -11, y: 0),
                            endPoint: CGPoint(x: 11, y: 0)
                           )
                         : .color(accent.opacity(0.56)),
                         style: StrokeStyle(lineWidth: selected ? 1.5 : 1.1,
                                            lineCap: .round))
        }

        context.fill(Path(ellipseIn: CGRect(x: 9.0, y: 8.0, width: 2.0, height: 2.0)),
                     with: .color(Color.white.opacity(selected ? 0.82 : 0.26)))
        context.fill(Path(ellipseIn: CGRect(x: 19.3, y: 3.2, width: 2.8, height: 2.8)),
                     with: .color(accent.opacity(selected ? 0.92 : 0.58)))
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
