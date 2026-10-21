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
                if sessionKind == "demo" || apiSession.isAuthorized {
                    ContentView()
                } else {
                    WelcomeView(
                        enterDemo: { sessionKind = "demo" },
                        onAuthenticated: { sessionKind = "account" }
                    )
                }
            }
            .environmentObject(profileStore)
            .environmentObject(chatLocationStore)
            .environmentObject(apiSession)
            .environmentObject(realtime)
        }
    }
}
