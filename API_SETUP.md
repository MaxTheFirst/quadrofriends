# Подключение backend

Клиент реализует контракт из [BACKEND_API.md](BACKEND_API.md) для входа, чатов, сообщений, передачи геопозиции в чате и WebSocket. Остальные экраны пока работают на `MockData`.

## Адрес сервера

Адрес задаётся build setting `API_BASE_URL` (Target → Build Settings → User-Defined) для Debug и Release и попадает в `Info.plist`. По умолчанию — `https://api.quadro.friends/v1`.

- Симулятор и сервер на том же Mac: `http://localhost:8080/v1`.
- iPhone и сервер в одной сети: `http://<имя-mac>.local:8080/v1`. `NSAllowsLocalNetworking` в `Info.plist` разрешает HTTP только для локальной сети, остальные адреса требуют HTTPS.

WebSocket строится из того же адреса: `…/v1/realtime`, схема `ws` для `http` и `wss` для `https`.

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
