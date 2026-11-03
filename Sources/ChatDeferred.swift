import SwiftUI

struct DeferredChatView: View {
    @EnvironmentObject private var app: AppState

    @ObservedObject private var burnFX = BurnFX.shared
    let chat: Chat
    @State private var ready = false

    var body: some View {
        ZStack {
            C.pageBg.ignoresSafeArea()
            if ready {
                ChatDetailView(chat: chat)
                    .transition(.opacity)
            } else {

                chatBackdrop
                    .ignoresSafeArea()
            }

            if burnFX.firing {
                FlameSweepOverlay()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .task {
            guard !ready else { return }
            await Task.yield()
            ready = true
        }
    }

    @ViewBuilder private var chatBackdrop: some View {
        ZStack {
            C.pageBg
            if !bgPath.isEmpty {
                RemoteImage(path: bgPath)
                    .id(bgPath)
            }
        }
    }

    private var bgPath: String {
        let synced = app.me?.chatBackgrounds?[chat.id] ?? ""
        if !synced.isEmpty, synced != "auto" { return synced }
        let per = ChatBgStore.shared.get(chat.id)
        if !per.isEmpty, per != "auto" { return per }
        let v = effectiveGlobalChatBackground(app.me?.chatBackground)
        if v.isEmpty || v == "auto" {
            let def = app.defaultChatBackground
            return def == "auto" ? "" : def
        }
        return v
    }
}
