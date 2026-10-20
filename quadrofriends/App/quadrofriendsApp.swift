//
//  quadrofriendsApp.swift
//  quadrofriends
//
//  Created by Максим Вершинин on 21.09.2026.
//

import SwiftUI

@main
struct quadrofriendsApp: App {
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var vkAuth = VKAuthManager()
    @StateObject private var chatLocationStore = ChatLocationSharingStore()
    @StateObject private var apiSession: APISession
    @StateObject private var realtime: RealtimeClient
    @AppStorage("sessionKind") private var sessionKind = "none"

    init() {
        let session = APISession()
        _apiSession = StateObject(wrappedValue: session)
        _realtime = StateObject(wrappedValue: RealtimeClient(session: session))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // Вход через VK действует, пока жива сессия нашего backend: её отзыв возвращает на экран входа.
                if sessionKind == "demo" || (sessionKind == "vk" && apiSession.isAuthorized) {
                    ContentView()
                } else {
                    WelcomeView(
                        vkAuth: vkAuth,
                        enterDemo: { sessionKind = "demo" },
                        signInWithVK: {
                            vkAuth.authorize { vkAccessToken in
                                Task {
                                    do {
                                        try await apiSession.signIn(vkAccessToken: vkAccessToken)
                                        sessionKind = "vk"
                                    } catch {
                                        vkAuth.showError("Не удалось войти: \(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                    )
                }
            }
            .environmentObject(profileStore)
            .environmentObject(vkAuth)
            .environmentObject(chatLocationStore)
            .environmentObject(apiSession)
            .environmentObject(realtime)
            .onOpenURL(perform: vkAuth.handleOpenURL)
        }
    }
}
