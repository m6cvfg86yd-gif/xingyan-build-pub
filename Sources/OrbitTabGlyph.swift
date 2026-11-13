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
                drawChat(context, line: line, fine: fine)
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

    private func drawChat(_ context: GraphicsContext,
                          line: StrokeStyle, fine: StrokeStyle) {
        let bubbleRect = CGRect(x: 2.6, y: 3.1, width: 18.8, height: 14.1)
        let bubble = Path(roundedRect: bubbleRect, cornerRadius: 7,
                          style: .continuous)
        var tail = Path()
        tail.move(to: CGPoint(x: 7.1, y: 16.2))
        tail.addLine(to: CGPoint(x: 4.9, y: 21.0))
        tail.addQuadCurve(to: CGPoint(x: 10.5, y: 17.0),
                          control: CGPoint(x: 7.0, y: 19.6))
        tail.closeSubpath()

        if selected {
            let fill = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [color, color.opacity(0.84)]),
                startPoint: CGPoint(x: 4, y: 3),
                endPoint: CGPoint(x: 19, y: 21)
            )
            context.fill(bubble, with: fill)
            context.fill(tail, with: fill)
        }
        context.stroke(bubble, with: .color(color), style: line)
        context.stroke(tail, with: .color(color), style: line)
    }

    private func drawContacts(_ context: GraphicsContext,
                              line: StrokeStyle, fine: StrokeStyle) {
        let mainHead = Path(ellipseIn: CGRect(x: 4.8, y: 3.8, width: 8.4, height: 8.4))
        var mainBody = Path()
        mainBody.move(to: CGPoint(x: 2.8, y: 20.3))
        mainBody.addCurve(to: CGPoint(x: 15.2, y: 20.3),
                          control1: CGPoint(x: 4.0, y: 13.5),
                          control2: CGPoint(x: 14.0, y: 13.5))

        let secondHead = Path(ellipseIn: CGRect(x: 14.4, y: 5.5, width: 6.3, height: 6.3))
        var secondBody = Path()
        secondBody.move(to: CGPoint(x: 14.1, y: 17.4))
        secondBody.addCurve(to: CGPoint(x: 21.7, y: 19.9),
                            control1: CGPoint(x: 16.7, y: 14.1),
                            control2: CGPoint(x: 20.1, y: 15.1))

        if selected {
            context.fill(mainHead, with: .color(color))
            context.fill(secondHead, with: .color(color.opacity(0.82)))
            context.stroke(mainBody,
                           with: .color(color),
                           style: StrokeStyle(lineWidth: 4.4,
                                              lineCap: .round,
                                              lineJoin: .round))
            context.stroke(secondBody,
                           with: .color(color.opacity(0.68)),
                           style: StrokeStyle(lineWidth: 2.3,
                                              lineCap: .round,
                                              lineJoin: .round))
        } else {
            context.stroke(mainHead, with: .color(color), style: line)
            context.stroke(secondHead, with: .color(color.opacity(0.78)), style: line)
            context.stroke(mainBody, with: .color(color), style: line)
            context.stroke(secondBody, with: .color(color.opacity(0.70)), style: fine)
        }
    }

    private func drawWorld(_ context: GraphicsContext,
                           line: StrokeStyle, fine: StrokeStyle) {
        let planetRect = CGRect(x: 3.1, y: 3.1, width: 17.8, height: 17.8)
        let planet = Path(ellipseIn: planetRect)
        if selected {
            context.fill(
                planet,
                with: .linearGradient(
                    Gradient(colors: [color, color.opacity(0.84)]),
                    startPoint: CGPoint(x: 5, y: 4),
                    endPoint: CGPoint(x: 20, y: 21)
                )
            )
        }
        context.stroke(planet, with: .color(color), style: line)

        context.drawLayer { layer in
            layer.clip(to: planet)
            let ink = selected ? Color.white.opacity(0.72) : color.opacity(0.58)
            let meridian = Path(ellipseIn: CGRect(x: 8.3, y: 3.1,
                                                  width: 8.4, height: 17.8))
            layer.stroke(meridian, with: .color(ink), style: fine)

            var latitude = Path()
            latitude.move(to: CGPoint(x: 3.6, y: 12))
            latitude.addCurve(to: CGPoint(x: 20.4, y: 12),
                              control1: CGPoint(x: 7.3, y: 8.8),
                              control2: CGPoint(x: 16.7, y: 8.8))
            layer.stroke(latitude, with: .color(ink), style: fine)

            var lowerLatitude = Path()
            lowerLatitude.move(to: CGPoint(x: 4.5, y: 17.2))
            lowerLatitude.addCurve(to: CGPoint(x: 19.5, y: 17.2),
                                   control1: CGPoint(x: 8.0, y: 14.8),
                                   control2: CGPoint(x: 16.0, y: 14.8))
            layer.stroke(lowerLatitude, with: .color(ink.opacity(0.74)), style: fine)
        }

        context.fill(Path(ellipseIn: CGRect(x: 7.2, y: 6.5, width: 2.2, height: 2.2)),
                     with: .color(Color.white.opacity(selected ? 0.28 : 0.12)))
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
