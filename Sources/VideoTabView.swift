import SwiftUI

struct VideoTabView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 42, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.primary)
                    }
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.24 : 0.07),
                            radius: 14, y: 6)

                    VStack(spacing: 7) {
                        Text(C.tabTextVideo)
                            .font(.system(size: 25, weight: .bold))
                        Text(Tr("正在开发中"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(Tr("视频内容正在准备中，后续会在这里提供原生浏览体验。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                }
            }
            .navigationTitle(C.tabTextVideo)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
