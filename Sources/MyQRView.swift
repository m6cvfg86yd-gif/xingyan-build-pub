import SwiftUI

struct MyQRViewOld: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [String] = []
    @State private var code = ""
    @State private var name = ""
    @State private var username = ""
    @State private var avatar = ""
    @State private var loading = true
    @State private var saved = false
    @State private var showScan = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("我的二维码"), back: { dismiss() }) {
                Button {
                    saveToAlbum()
                } label: {
                    Text(saved ? Tr("已存") : Tr("保存"))
                        .font(pf(16, .medium))
                        .foregroundColor(rows.isEmpty ? C.subLabel : C.green)
                        .frame(height: L.navH)
                        .padding(.trailing, 16)
                }
                .buttonStyle(.plain)
                .disabled(rows.isEmpty)
            }

            ScrollView {
                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.white)
                        if loading {
                            ProgressView()
                        } else if rows.isEmpty {
                            Text(Tr("二维码生成失败，稍后再试"))
                                .font(pf(13.5)).foregroundColor(C.subLabel)
                        } else {

                            QRCanvas(rows: rows).frame(width: 228, height: 228)
                                .frame(width: 228, height: 228)
                        }
                    }
                    .frame(width: 256, height: 256)
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)

                    HStack(spacing: 12) {
                        Avatar(path: avatar, size: 46, radius: 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name).font(pf(16, .medium)).foregroundColor(C.label).lineLimit(1)
                            Text(Tr("星言号：") + (username.isEmpty ? "-" : username))
                                .font(pf(12.5)).foregroundColor(C.subLabel)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 68)
                    .background { CardGlassBox(radius: 7) }
                    .padding(.horizontal, 24)

                    Text(Tr("用 App 的「发现 → 扫一扫」扫这张，就能加我好友"))
                        .font(pf(12.5)).foregroundColor(C.subLabel)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)

                    Button {
                        showScan = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode.viewfinder")
                            Text(Tr("扫一扫"))
                        }
                        .font(pf(15, .medium))
                        .foregroundColor(C.green)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background { CardGlassBox(radius: 999) }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    Spacer().frame(height: 30)
                }
                .padding(.top, 20)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()

        .modifier(BrightenScreen())
        .fullScreenCover(isPresented: $showScan) {
            ScannerView { text in handleScanned(text, app: app) }
        }
        .task {
            let r = await API.shared.myQRCode()
            code = r.code
            rows = r.rows
            name = r.user?.name ?? (app.me?.name ?? "")
            username = r.user?.username ?? (app.me?.username ?? "")
            avatar = r.user?.avatarPath ?? (app.me?.avatarPath ?? "")
            loading = false
        }
    }

    private func saveToAlbum() {
        guard !rows.isEmpty else { return }
        let card = VStack(spacing: 14) {
            ZStack {
                QRCanvas(rows: rows).frame(width: 520, height: 520)
                Avatar(path: avatar, size: 100, radius: 18)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
            }
            .frame(width: 520, height: 520)
            Text(name).font(pfStyled(size: 26, weight: .semibold))
            Text(Tr("星言号：") + username).font(pfStyled(size: 20)).foregroundColor(.gray)
            Text(Tr("扫一扫，加我好友")).font(pfStyled(size: 20)).foregroundColor(.gray)
        }
        .padding(40)
        .background(Color.white)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        if let img = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            saved = true
            app.show(Tr("二维码已存到相册"))
            return
        }
        app.show(Tr("保存失败，可以截图"))
    }
}
