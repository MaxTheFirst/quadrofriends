# Подключение backend

Клиент реализует контракт из [BACKEND_API.md](BACKEND_API.md) для входа, чатов, сообщений, передачи геопозиции в чате и WebSocket. Остальные экраны пока работают на `MockData`.

## Адрес сервера

Адрес задаётся через `API_BASE_URL` в `Config.xcconfig` и попадает в `Info.plist`. Для локального переопределения скопируйте `Local.xcconfig.example` в `Local.xcconfig` и задайте там `API_BASE_URL`; этот файл игнорируется Git. Backend ([quadrofriends-back](https://github.com/MaxTheFirst/quadrofriends-back)) публикует ручки под префиксом `/api`, а не `/v1` из спецификации.

- Debug и Release по умолчанию: `https://api.pdfshare.ru/api`.
- Для локальной разработки можно переопределить `API_BASE_URL` в `Local.xcconfig`: `http:$(SLASH)$(SLASH)localhost:8080/api` для симулятора или адрес Mac в той же сети для iPhone. Переменная `SLASH` нужна, чтобы `//` в URL не считались началом комментария в xcconfig. `NSAllowsLocalNetworking` в `Info.plist` разрешает HTTP только для локальной сети, остальные адреса требуют HTTPS.

WebSocket строится из того же адреса: `…/api/realtime`, схема `ws` для `http` и `wss` для `https`.

Для регистрации и входа достаточно работающего backend. Подтверждение почты не требуется. Swagger с профилем `debug`: `http://localhost:8080/external/swagger-ui/index.html`.

### Особенности сервера

- Неизвестные поля в JSON отклоняются (`fail-on-unknown-properties`): клиент отправляет только поля из DTO и не кодирует `nil`.
- `Idempotency-Key` должен быть UUID.
- Время приходит с микросекундами (`…:00.123456Z`); `APIClient.parseISO8601` приводит дробную часть к миллисекундам.
- `accuracy_m` позиции — от 0 до 100 м; более грубые точки GPS не отправляются.

## Вход

1. Экран входа отправляет `POST /sessions` с `grant_type=password`, email и паролем. Экран регистрации отправляет `grant_type=register`, email, пароль, имя и фамилию; username, год рождения и город необязательны.
2. Успешная регистрация сразу создаёт сессию. `APISession` хранит токены в Keychain.
3. Access token подставляется в `Authorization`. За 30 секунд до истечения или после ответа `401` клиент вызывает `POST /sessions` с `grant_type=refresh` и `Idempotency-Key`; параллельные запросы ждут одно обновление.
4. Отказ сервера в refresh token завершает сессию и возвращает на экран входа. «Вернуться к экрану входа» в профиле вызывает `DELETE /sessions/{id}`.

Деморежим работает без сервера на демонстрационных данных.

## Где что лежит

- `Core/Networking/` — `APIClient` (JSON snake_case, единая ошибка, `Idempotency-Key`), `APISession`, `KeychainStore`, `RealtimeClient`, `RemoteImageLoader`.
- `Features/Chats/API/` — DTO, `ChatsAPI` (ручки), `ChatsRepository` (сервер и демо, преобразование DTO в модели экранов).
- `ChatLocationSharingStore` создаёт передачу через `POST /location-shares`, отправляет позиции не чаще раза в 5 секунд и получает чужие позиции из `GET /users/me/visible-location-shares`, `GET /chats/{id}/location-shares` и WebSocket.

## Что проверить с сервером

- Регистрация: email, пароль, имя и фамилия → `POST /sessions` → список чатов. Затем выход и вход по тому же email и паролю.
- Отправка сообщения без сети показывает «Не отправлено»; нажатие на сообщение повторяет отправку с тем же `Idempotency-Key`.
- Сообщение с другого устройства приходит без обновления экрана; после выключения Wi-Fi и включения лента дочитывается.
- Прокрутка вверх подгружает старые сообщения, позиция ленты не прыгает.
- Галочка меняется на «прочитано», когда собеседник открывает чат.
