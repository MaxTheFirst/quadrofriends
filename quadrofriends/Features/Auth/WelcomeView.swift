import SwiftUI

struct WelcomeView: View {
    @ObservedObject var vkAuth: VKAuthManager
    let enterDemo: () -> Void
    let signInWithVK: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    Spacer(minLength: 80)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Своих находят\nв пути.")
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .tracking(-1.5)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Записывай маршруты, открывай новые места и находи компанию для поездок.")
                            .font(.system(size: 16, weight: .medium))
                            .lineSpacing(3)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.top, 12)
                            .padding(.bottom, 30)

                        Button(action: signInWithVK) {
                            HStack(spacing: 12) {
                                Image("VKSignInLogo")
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 36, height: 36)

                                Text("Войти через VK")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.07, green: 0.08, blue: 0.10))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Войти или зарегистрироваться через VK")
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            GeometryReader { geometry in
                Image("RouteForest")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.48), location: 0),
                                .init(color: .black.opacity(0.08), location: 0.34),
                                .init(color: .black.opacity(0.15), location: 0.56),
                                .init(color: .black.opacity(0.85), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .ignoresSafeArea()
        }
        .alert("VK ID", isPresented: $vkAuth.showingError) {
            Button("Понятно", role: .cancel) { }
        } message: {
            Text(vkAuth.errorMessage)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.48, blue: 0.12))

            Text("КВАДРО ДРУЗЬЯ")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(1.7)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Деморежим", action: enterDemo)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(.black.opacity(0.26), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1) }
                .accessibilityLabel("Посмотреть приложение без входа")
        }
    }
}
