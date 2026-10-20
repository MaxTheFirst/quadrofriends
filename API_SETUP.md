# Подключение backend

Клиент реализует контракт из [BACKEND_API.md](BACKEND_API.md) для входа, чатов, сообщений, передачи геопозиции в чате и WebSocket. Остальные экраны пока работают на `MockData`.

## Адрес сервера

Адрес задаётся build setting `API_BASE_URL` (Target → Build Settings → User-Defined) и попадает в `Info.plist`. Backend ([quadrofriends-back](https://github.com/MaxTheFirst/quadrofriends-back)) публикует ручки под префиксом `/api`, а не `/v1` из спецификации.

- Debug по умолчанию: `http://localhost:8080/api` — симулятор и сервер на одном Mac.
- iPhone и сервер в одной сети: `http://<имя-mac>.local:8080/api`. `NSAllowsLocalNetworking` в `Info.plist` разрешает HTTP только для локальной сети, остальные адреса требуют HTTPS.
- Release: `https://api.quadro.friends/api` — заменить на реальный адрес, когда сервер будет развёрнут.

WebSocket строится из того же адреса: `…/api/realtime`, схема `ws` для `http` и `wss` для `https`.

Для входа через VK на сервере должен быть задан `VK_CLIENT_ID` (`.env`). Swagger с профилем `debug`: `http://localhost:8080/external/swagger-ui.html`.

### Особенности сервера

- Неизвестные поля в JSON отклоняются (`fail-on-unknown-properties`): клиент отправляет только поля из DTO и не кодирует `nil`.
- `Idempotency-Key` должен быть UUID.
- Время приходит с микросекундами (`…:00.123456Z`); `APIClient.parseISO8601` приводит дробную часть к миллисекундам.
- `accuracy_m` позиции — от 0 до 100 м; более грубые точки GPS не отправляются.

## Вход

1. VK ID SDK возвращает access token VK.
2. `APISession.signIn(vkAccessToken:)` вызывает `POST /sessions` с `grant_type=vk` и сохраняет сессию в Keychain.
3. Access token подставляется в `Authorization`. За 30 секунд до истечения или после ответа `401` клиент один раз вызывает `POST /sessions` с `grant_type=refresh`; параллельные запросы ждут одно обновление.
4. Отказ сервера в refresh token завершает сессию и возвращает на экран входа. «Вернуться к экрану входа» в профиле вызывает `DELETE /sessions/{id}`.

Деморежим работает без сервера на демонстрационных данных.

## Где что лежит

- `Core/Networking/` — `APIClient` (JSON snake_case, единая ошибка, `Idempotency-Key`), `APISession`, `KeychainStore`, `RealtimeClient`, `RemoteImageLoader`.
- `Features/Chats/API/` — DTO, `ChatsAPI` (ручки), `ChatsRepository` (сервер и демо, преобразование DTO в модели экранов).
- `ChatLocationSharingStore` создаёт передачу через `POST /location-shares`, отправляет позиции не чаще раза в 5 секунд и получает чужие позиции из `GET /users/me/visible-location-shares`, `GET /chats/{id}/location-shares` и WebSocket.

## Что проверить с сервером

- Первый вход: VK token → `POST /sessions` → список чатов.
- Отправка сообщения без сети показывает «Не отправлено»; нажатие на сообщение повторяет отправку с тем же `Idempotency-Key`.
- Сообщение с другого устройства приходит без обновления экрана; после выключения Wi-Fi и включения лента дочитывается.
- Прокрутка вверх подгружает старые сообщения, позиция ленты не прыгает.
- Галочка меняется на «прочитано», когда собеседник открывает чат.
