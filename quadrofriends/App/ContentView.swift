                                    //
//  ContentView.swift
//  quadrofriends
//
//  Created by Максим Вершинин on 21.09.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var chatLocationStore: ChatLocationSharingStore
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
                NavigationStack {
                    ChatsView()
                }
            }

            Tab("Профиль", systemImage: "person.crop.circle.fill", value: 3) {
                NavigationStack {
                    ProfileView()
                }
            }
        }
        .tint(Color.brandOlive)
        .preferredColorScheme(appTheme.colorScheme)
        .onAppear { chatLocationStore.setDemoDataEnabled(sessionKind == "demo") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { chatLocationStore.removeExpiredShares() }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ProfileStore())
        .environmentObject(VKAuthManager())
        .environmentObject(ChatLocationSharingStore())
}
