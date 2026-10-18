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
    @AppStorage("sessionKind") private var sessionKind = "none"

    var body: some Scene {
        WindowGroup {
            Group {
                if sessionKind == "demo" || (sessionKind == "vk" && vkAuth.hasAuthorizedSession) {
                    ContentView()
                } else {
                    WelcomeView(
                        vkAuth: vkAuth,
                        enterDemo: { sessionKind = "demo" },
                        signInWithVK: {
                            vkAuth.authorize {
                                sessionKind = "vk"
                            }
                        }
                    )
                }
            }
            .environmentObject(profileStore)
            .environmentObject(vkAuth)
            .environmentObject(chatLocationStore)
            .onOpenURL(perform: vkAuth.handleOpenURL)
        }
    }
}
