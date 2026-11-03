import SwiftUI

private let hBlue   = Color(hex: 0x007DFF)
private let hBlueBg = Color(hex: 0xE8F3FF)
private let hInk    = Color(hex: 0x181818)
private let hInk2   = Color(hex: 0x666666)
private let hInk3   = Color(hex: 0x999999)
private let hBg     = Color(hex: 0xF5F6F7)
private let hLine   = Color(hex: 0xE8EAED)
private let hGreen  = Color(hex: 0x2E7D32)

struct ContactCardNew: View {
    let name: String
    let idLine: String

    let avatarPath: String
    let isEyes: Bool
    let remark: String
    let phone: String
    let momentCount: Int

    let momentsRange: String
    let networkProvince: String
    let deviceModel: String
    let onClose: () -> Void
    let onMessage: () -> Void
    let onVoice: () -> Void
    let onVideo: () -> Void
    let onMoments: (() -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            hBg.ignoresSafeArea()
            VStack(spacing: 0) {
                nav
                ScrollView {
                    VStack(spacing: 0) {
                        hero
                        if !detailRows.isEmpty {
                            sectionTitle("资料")
                            card {
                                ForEach(Array(detailRows.enumerated()), id: \.offset) { idx, row in
                                    if idx > 0 { line }
                                    hRow(row.0, row.1)
                                }
                            }
                        }

                        sectionTitle("生活圈", trailing: momentCount > 0 ? "\(momentCount) 条" : "")
                            card {
                                Button {
                                    onMoments?()
                                } label: {
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(hBlueBg)
                                            .frame(width: 44, height: 44)
                                            .overlay(Image(systemName: "photo.on.rectangle.angled")
                                                .font(.system(size: 18)).foregroundColor(hBlue))
                        Text(momentCount > 0 ? "看 TA 的生活圈" : momentEmptyText)
                            .font(pf(16)).foregroundColor(momentCount > 0 ? hInk : hInk3)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold)).foregroundColor(hInk3)
                                    }
                                    .padding(.horizontal, 16).frame(height: 60)
                                }
                                .buttonStyle(.plain)
                            }
                        Spacer(minLength: 24)
                    }
                }
            }
        }
    }

    private var detailRows: [(String, String)] {
        var list: [(String, String)] = []
        if !remark.isEmpty { list.append(("备注", remark)) }
        if !phone.isEmpty { list.append(("手机号", phone)) }
        list.append(("网络属地", networkProvince))
        list.append(("手机型号", deviceModel))
        return list
    }

    private var momentEmptyText: String {
        switch momentsRange {
        case "3d": return "朋友仅展示最近三天的生活圈"
        case "6m": return "朋友仅展示最近半年的生活圈"
        default:   return "暂无生活圈动态"
        }
    }

    private var nav: some View {
        HStack {
            Button { onClose() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(hInk)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(name).font(pf(17, .semibold)).foregroundColor(hInk)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 17)).foregroundColor(hInk)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color.white)
    }

    private var hero: some View {
        VStack(spacing: 0) {

            HStack(alignment: .center, spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if isEyes {
                            JarvisEyesAvatar(size: 72)
                        } else {
                            Avatar(path: avatarPath, size: 72, radius: 36)
                        }
                    }
                    .frame(width: 72, height: 72)
                    Circle().fill(hGreen).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(name).font(pf(20, .semibold)).foregroundColor(hInk)
                    Text(idLine).font(pf(14)).foregroundColor(hInk3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                pill("发消息", primary: true, action: onMessage)
                pill("语音", primary: false, action: onVoice)
                pill("视频", primary: false, action: onVideo)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color(hex: 0x20000000), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func sectionTitle(_ t: String, trailing: String? = nil) -> some View {
        HStack {
            Text(t).font(pf(18, .medium)).foregroundColor(hInk)
            Spacer()
            if let tr = trailing { Text(tr).font(pf(14)).foregroundColor(hInk3) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color(hex: 0x20000000), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)
    }

    private func hRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(pf(16)).foregroundColor(hInk)
            Spacer()
            Text(v).font(pf(14)).foregroundColor(hInk3)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var line: some View {
        Rectangle().fill(hLine).frame(height: 1).padding(.leading, 16)
    }

    private func pill(_ text: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Text(text)
                .font(pf(16, .medium))
                .foregroundColor(primary ? .white : hBlue)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Group {
                        if primary { Capsule().fill(hBlue) } else { Capsule().stroke(hBlue, lineWidth: 1.5) }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}
