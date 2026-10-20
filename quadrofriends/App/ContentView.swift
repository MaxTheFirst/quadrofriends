                                    //
//  ContentView.swift
//  quadrofriends
//
//  Created by Максим Вершинин on 21.09.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var chatLocationStore: ChatLocationSharingStore
    @EnvironmentObject private var apiSession: APISession
    @EnvironmentObject private var realtime: RealtimeClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0
    @AppStorage("appTheme") private var appTheme = AppTheme.system
    @AppStorage("sessionKind") private var sessionKind = "none"

    var body: some View {
        TabView(selection: $selection) {
            Tab("Карта", systemImage: "map.fill", value: 0) {
                NavigationStack {
                    MapHomeView(appTheme: $appTheme)
                }
            }

            Tab("Маршруты", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: 1) {
                NavigationStack {
                    MyRoutesView()
                }
            }

            Tab("Чаты", systemImage: "bubble.left.and.bubble.right.fill", value: 2) {
                ChatsTab()
            }

            Tab("Профиль", systemImage: "person.crop.circle.fill", value: 3) {
                NavigationStack {
                    ProfileView()
                }
            }
        }
        .tint(Color.brandOlive)
        .preferredColorScheme(appTheme.colorScheme)
        .onAppear {
            chatLocationStore.setDemoDataEnabled(sessionKind == "demo")
            chatLocationStore.connect(
                session: usesBackend ? apiSession : nil,
                realtime: usesBackend ? realtime : nil
            )
            if usesBackend { realtime.start() }
        }
        .onDisappear {
            realtime.stop()
            chatLocationStore.connect(session: nil, realtime: nil)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                chatLocationStore.removeExpiredShares()
                if usesBackend { realtime.start() }
            case .background:
                // В фоне WebSocket не держим: новые сообщения придут push-уведомлением.
                realtime.stop()
            default:
                break
            }
        }
    }

    private var usesBackend: Bool {
        sessionKind == "vk" && apiSession.isAuthorized
    }
}

#Preview {
    let session = APISession()
    ContentView()
        .environmentObject(ProfileStore())
        .environmentObject(VKAuthManager())
        .environmentObject(ChatLocationSharingStore())
        .environmentObject(session)
        .environmentObject(RealtimeClient(session: session))
}
