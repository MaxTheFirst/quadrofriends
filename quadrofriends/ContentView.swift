                                    //
//  ContentView.swift
//  quadrofriends
//
//  Created by Максим Вершинин on 21.09.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var selection = 0
    @AppStorage("appTheme") private var appTheme = AppTheme.system

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
    }
}

#Preview {
    ContentView()
}
