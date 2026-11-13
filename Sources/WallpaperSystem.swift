import SwiftUI
import UIKit

struct WallpaperCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onApply: (UIImage) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let viewport = proxy.size
            let fitted = aspectFillSize(image.size, in: viewport)

            ZStack {
                Color.black.ignoresSafeArea()
                cropCanvas(viewport: viewport, fitted: fitted)
                editorChrome(viewport: viewport)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(false)
    }

    private func cropCanvas(viewport: CGSize, fitted: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: fitted.width, height: fitted.height)
            .scaleEffect(zoom)
            .offset(offset)
            .frame(width: viewport.width, height: viewport.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture(viewport: viewport, fitted: fitted))
            .simultaneousGesture(zoomGesture(viewport: viewport, fitted: fitted))
            .onTapGesture(count: 2, perform: resetCrop)
    }

    private func dragGesture(viewport: CGSize, fitted: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let proposed = CGSize(
                    width: settledOffset.width + value.translation.width,
                    height: settledOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed,
                                       fitted: fitted,
                                       viewport: viewport,
                                       zoom: zoom)
            }
            .onEnded { _ in settledOffset = offset }
    }

    private func zoomGesture(viewport: CGSize, fitted: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(3.2, max(1, settledZoom * value))
                offset = clampedOffset(offset,
                                       fitted: fitted,
                                       viewport: viewport,
                                       zoom: zoom)
            }
            .onEnded { _ in
                settledZoom = zoom
                settledOffset = offset
            }
    }

    private func resetCrop() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            zoom = 1
            settledZoom = 1
            offset = .zero
            settledOffset = .zero
        }
    }

    private func editorChrome(viewport: CGSize) -> some View {
        VStack {
            editorTopBar(viewport: viewport)
            Spacer(minLength: 0)
            editorBottomBar
        }
        .background {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.48),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.54)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func editorTopBar(viewport: CGSize) -> some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black.opacity(0.28)))
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.7))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(Tr("移动和缩放"))
                    .font(pf(16, .semibold))
                    .foregroundStyle(.white)
                Text(Tr("双指缩放，拖动调整显示范围"))
                    .font(pf(11.5))
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer(minLength: 0)

            Button {
                onApply(render(viewport: viewport))
            } label: {
                Text(Tr("设定"))
                    .font(pf(14.5, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.17)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, max(10, L.safeTop + 4))
    }

    private var editorBottomBar: some View {
        HStack(spacing: 10) {
            Image(systemName: scheme == .dark ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(Tr(scheme == .dark
                    ? "深色模式会自动生成自然黑模糊"
                    : "浅色模式保留完整全景"))
                .font(pf(12, .medium))
                .foregroundStyle(.white.opacity(0.78))
            Spacer(minLength: 0)
            Text("\(Int((zoom * 100).rounded()))%")
                .font(pf(11.5, .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .monospacedDigit()
        }
        .padding(.horizontal, 15)
        .frame(height: 46)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.13), lineWidth: 0.7))
        }
        .padding(.horizontal, 18)
        .padding(.bottom, max(14, L.safeBottom + 8))
    }

    private func aspectFillSize(_ source: CGSize, in viewport: CGSize) -> CGSize {
        guard source.width > 1, source.height > 1,
              viewport.width > 1, viewport.height > 1 else {
            return CGSize(width: max(1, viewport.width), height: max(1, viewport.height))
        }
        let scale = max(viewport.width / source.width,
                        viewport.height / source.height)
        return CGSize(width: source.width * scale,
                      height: source.height * scale)
    }

    private func clampedOffset(_ proposed: CGSize,
                               fitted: CGSize,
                               viewport: CGSize,
                               zoom: CGFloat) -> CGSize {
        let scaledWidth = fitted.width * zoom
        let scaledHeight = fitted.height * zoom
        let maxX = max(0, (scaledWidth - viewport.width) * 0.5)
        let maxY = max(0, (scaledHeight - viewport.height) * 0.5)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    private func render(viewport: CGSize) -> UIImage {
        let targetScale = min(3, 3200 / max(1, max(viewport.width, viewport.height)))
        let target = CGSize(width: max(1, viewport.width * targetScale),
                            height: max(1, viewport.height * targetScale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            let fit = max(target.width / max(1, image.size.width),
                          target.height / max(1, image.size.height)) * zoom
            let drawSize = CGSize(width: image.size.width * fit,
                                  height: image.size.height * fit)
            let xOffset = offset.width / max(1, viewport.width) * target.width
            let yOffset = offset.height / max(1, viewport.height) * target.height
            let origin = CGPoint(
                x: (target.width - drawSize.width) * 0.5 + xOffset,
                y: (target.height - drawSize.height) * 0.5 + yOffset
            )
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}
