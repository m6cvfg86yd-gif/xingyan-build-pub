import SwiftUI
import SwiftUI
import UIKit

struct SwitchAccountView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var growth = GrowthStore.shared

    @State private var adding = false
    @State private var busy = ""
    @State private var note = ""

    private var me: String { app.me?.username ?? "" }

    var body: some View {
        ZStack {
            C.pageBg.ignoresSafeArea()
            accountWatermark

            VStack(spacing: 0) {

                HStack(spacing: 0) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(C.label)
                            .frame(height: L.navH)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Text(Tr("切换账号")).font(pf(17, .semibold)).foregroundColor(C.label)
                    Spacer(minLength: 0)
                    Color.clear.frame(width: 51, height: L.navH)
                }
                .frame(height: L.navH)
                .background(accountTopMask)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        accountHero

                        VStack(spacing: 10) {
                            ForEach(app.accounts) { acct in
                                accountRow(acct)
                            }
                            addRow
                        }

                        if !note.isEmpty {
                            Text(note)
                                .font(pf(13))
                                .foregroundColor(Color(hexString: "#FA5151"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.top, 2)
                        }

                        HStack(spacing: 7) {
                            Image(systemName: "lock.shield.fill")
                            Text(Tr("已登录账号只保存在这台设备"))
                        }
                        .font(pf(11.5))
                        .foregroundColor(C.subLabel)
                        .padding(.top, 2)
                        .padding(.bottom, max(24, L.safeBottom))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 26)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .fullScreenCover(isPresented: $adding) {
            HarmonyLoginView()
                .environmentObject(app)
        }
    }

    private var accountHero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(OrbitTheme.jadeSoft)
                    .frame(width: 78, height: 78)
                Circle()
                    .stroke(OrbitTheme.gold.opacity(0.45), lineWidth: 1.1)
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-18))
                brandLogo(size: 60)
            }

            VStack(spacing: 5) {
                Text("星言 Luchat")
                    .font(pf(22, .semibold))
                    .foregroundColor(C.label)
                Text(Tr("轻触头像以切换账号"))
                    .font(pf(13.5))
                    .foregroundColor(C.subLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var accountWatermark: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .stroke(OrbitTheme.jade.opacity(0.07), lineWidth: 1)
                    .frame(width: min(geo.size.width * 0.86, 360))
                    .offset(x: geo.size.width * 0.30, y: -geo.size.height * 0.23)
                Circle()
                    .stroke(OrbitTheme.gold.opacity(0.06), lineWidth: 1)
                    .frame(width: min(geo.size.width * 0.62, 270))
                    .offset(x: -geo.size.width * 0.38, y: geo.size.height * 0.32)
                brandLogo(size: min(geo.size.width * 0.72, 300))
                    .opacity(0.035)
                    .rotationEffect(.degrees(-8))
                    .offset(x: geo.size.width * 0.30, y: -geo.size.height * 0.10)
                Text("LUCHAT")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .tracking(8)
                    .foregroundColor(OrbitTheme.jade.opacity(0.025))
                    .rotationEffect(.degrees(-8))
                    .offset(x: -geo.size.width * 0.18, y: geo.size.height * 0.32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private var accountTopMask: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                C.navBg.opacity(0.97)

                LinearGradient(
                    colors: [
                        C.red.opacity(0.20),
                        Color(hex: 0xFF8B78).opacity(0.075),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .stroke(C.red.opacity(0.20), lineWidth: 0.8)
                    .frame(width: geo.size.height * 1.7,
                           height: geo.size.height * 1.7)
                    .offset(x: geo.size.width * 0.31,
                            y: geo.size.height * 0.58)

                Circle()
                    .stroke(C.red.opacity(0.11), lineWidth: 0.7)
                    .frame(width: geo.size.height * 1.18,
                           height: geo.size.height * 1.18)
                    .offset(x: -geo.size.width * 0.34,
                            y: geo.size.height * 0.70)

                Capsule()
                    .fill(C.red.opacity(0.10))
                    .frame(width: geo.size.width * 0.34, height: 1.2)
                    .rotationEffect(.degrees(-18))
                    .offset(x: geo.size.width * 0.20,
                            y: -geo.size.height * 0.17)

                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(C.red.opacity(index == 1 ? 0.24 : 0.12))
                            .frame(width: index == 1 ? 3 : 2,
                                   height: index == 1 ? 3 : 2)
                    }
                }
                .offset(x: geo.size.width * 0.29,
                        y: -geo.size.height * 0.26)

                LinearGradient(
                    colors: [C.red.opacity(0.0), C.red.opacity(0.56)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 1)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func brandLogo(size: CGFloat) -> some View {
        if let image = UIImage(named: "AppIcon60x60@3x")
            ?? UIImage(named: "AppIcon60x60@2x") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(OrbitTheme.jadeDeep)
                .frame(width: size, height: size)
                .overlay(
                    Text("星")
                        .font(.system(size: size * 0.48, weight: .semibold))
                        .foregroundColor(.white)
                )
        }
    }

    @ViewBuilder
    private func accountRow(_ a: SavedAccount) -> some View {
        let current = (a.username == me)
        Button {
            tap(a, current: current)
        } label: {

            HStack(spacing: 12) {
                Avatar(path: a.avatar, size: 48, radius: 7, level: levelOf(a))
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(a.nickname.isEmpty ? a.username : a.nickname)
                        .font(pf(17))
                        .foregroundColor(C.label)
                        .lineLimit(1)
                    Text(a.username)
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if busy == a.username {
                    ProgressView()
                } else if current {
                    Text(Tr("当前使用"))
                        .font(pf(13.5))
                        .foregroundColor(C.subLabel)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 80)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(current ? OrbitTheme.jade.opacity(0.42) : C.navLine, lineWidth: 0.7)
            )
            .shadow(color: Color.black.opacity(0.035), radius: 8, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !current {
                Button(role: .destructive) { remove(a) } label: {
                    Label(Tr("从这台设备移除"), systemImage: "trash")
                }
            }
        }
    }

    private var addRow: some View {
        Button { adding = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.dyn(0xEDEDED, 0x2C2C2E))
                        .frame(width: 48, height: 48)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(C.subLabel)
                }
                Text(Tr("添加账号"))
                    .font(pf(17))
                    .foregroundColor(C.label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 80)
            .background(C.cardBg.opacity(0.84))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(OrbitTheme.jade.opacity(0.28),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func levelOf(_ a: SavedAccount) -> Int {
        if a.username == me { return max(1, growth.shownLevel) }
        if let lv = app.contacts.first(where: { $0.username == a.username })?.qqLevel, lv > 0 { return lv }
        return 0
    }

    private func tap(_ a: SavedAccount, current: Bool) {
        guard !current, busy.isEmpty else { return }
        switchTo(a)
    }

    private func switchTo(_ a: SavedAccount) {
        note = ""
        busy = a.username
        Task {
            let saved = AccountStore.token(for: a.username)
            guard !saved.isEmpty else {
                busy = ""
                note = Tr("这个账号的登录状态过期了，重新输一次密码就行")
                adding = true
                return
            }
            let ok = await app.quickLogin(token: saved,
                                          username: a.username,
                                          switchingAccount: true)
            busy = ""
            if ok {
                dismiss()
            } else {
                note = Tr("这个账号的登录状态过期了，重新输一次密码就行")
                adding = true
            }
        }
    }

    private func remove(_ a: SavedAccount) {
        AccountStore.remove(username: a.username)
        app.accounts = AccountStore.load()
        app.show(Tr("已移除") + "「" + a.nickname + "」")
    }
}
