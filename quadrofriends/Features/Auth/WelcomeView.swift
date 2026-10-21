import SwiftUI

private enum AuthMode {
    case signIn
    case register
}

struct WelcomeView: View {
    @EnvironmentObject private var apiSession: APISession

    let enterDemo: () -> Void
    let onAuthenticated: () -> Void

    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmationVisible = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var birthYear = ""
    @State private var city = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 56)
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
                            .padding(.bottom, 28)
                        authForm
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
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
                                .init(color: .black.opacity(0.62), location: 0),
                                .init(color: .black.opacity(0.36), location: 0.34),
                                .init(color: .black.opacity(0.62), location: 0.56),
                                .init(color: .black.opacity(0.9), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private var authForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .register ? "Создать аккаунт" : "Войти в аккаунт")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .padding(.bottom, 4)

            TextField("", text: $email, prompt: Text("Почта").foregroundColor(.white.opacity(0.7)))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .authField()

            passwordInput("Пароль", text: $password, isVisible: $isPasswordVisible, isNewPassword: mode == .register)
                .onSubmit { if mode == .signIn { submit() } }

            if mode == .register {
                passwordInput("Повторите пароль", text: $passwordConfirmation, isVisible: $isConfirmationVisible, isNewPassword: true)
                TextField("", text: $firstName, prompt: Text("Имя").foregroundColor(.white.opacity(0.7)))
                    .textContentType(.givenName)
                    .authField()
                TextField("", text: $lastName, prompt: Text("Фамилия").foregroundColor(.white.opacity(0.7)))
                    .textContentType(.familyName)
                    .authField()
                TextField("", text: $username, prompt: Text("Имя пользователя (необязательно)").foregroundColor(.white.opacity(0.7)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .authField()
                HStack(spacing: 12) {
                    TextField("", text: $birthYear, prompt: Text("Год рождения").foregroundColor(.white.opacity(0.7)))
                        .keyboardType(.numberPad)
                        .authField()
                    TextField("", text: $city, prompt: Text("Город").foregroundColor(.white.opacity(0.7)))
                        .textContentType(.addressCity)
                        .authField()
                }
                Text("Почту подтверждать не нужно. Пароль — от 8 символов.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.82))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(red: 1, green: 0.79, blue: 0.72))
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Button(action: submit) {
                HStack(spacing: 10) {
                    if isSubmitting { ProgressView().tint(.black) }
                    Text(mode == .register ? "Зарегистрироваться" : "Войти")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.07, green: 0.08, blue: 0.10))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .padding(.top, 8)

            Button {
                mode = mode == .signIn ? .register : .signIn
                password = ""
                passwordConfirmation = ""
                isPasswordVisible = false
                isConfirmationVisible = false
                errorMessage = nil
            } label: {
                Text(mode == .register ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Зарегистрироваться")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
        }
    }

    private func passwordInput(
        _ placeholder: String,
        text: Binding<String>,
        isVisible: Binding<Bool>,
        isNewPassword: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Group {
                if isVisible.wrappedValue {
                    TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.7)))
                        .textContentType(isNewPassword ? .newPassword : .password)
                } else {
                    SecureField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.7)))
                        .textContentType(isNewPassword ? .newPassword : .password)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.82))
            .accessibilityLabel(isVisible.wrappedValue ? "Скрыть: \(placeholder)" : "Показать: \(placeholder)")
        }
        .authField()
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

    private func submit() {
        guard !isSubmitting else { return }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), !normalizedEmail.contains(" ") else {
            errorMessage = "Введите корректную почту."
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Введите пароль."
            return
        }

        let registration = mode == .register
        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if registration {
            guard !trimmedFirstName.isEmpty, !trimmedLastName.isEmpty else {
                errorMessage = "Укажите имя и фамилию."
                return
            }
            guard password.count >= 8, password.utf8.count <= 72 else {
                errorMessage = "Пароль должен содержать от 8 символов до 72 байт."
                return
            }
            guard !passwordConfirmation.isEmpty else {
                errorMessage = "Повторите пароль."
                return
            }
            guard password == passwordConfirmation else {
                errorMessage = "Пароли не совпадают."
                return
            }
        }

        let trimmedYear = birthYear.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedYear = Int(trimmedYear)
        if registration, !trimmedYear.isEmpty {
            guard let parsedYear, (1900...Calendar.current.component(.year, from: Date())).contains(parsedYear) else {
                errorMessage = "Укажите корректный год рождения."
                return
            }
        }

        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                if registration {
                    try await apiSession.register(
                        email: normalizedEmail, password: password,
                        firstName: trimmedFirstName, lastName: trimmedLastName,
                        username: optional(username), birthYear: parsedYear, city: optional(city)
                    )
                } else {
                    try await apiSession.signIn(email: normalizedEmail, password: password)
                }
                password = ""
                passwordConfirmation = ""
                onAuthenticated()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension View {
    func authField() -> some View {
        font(.system(size: 16))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.3)) }
    }
}
