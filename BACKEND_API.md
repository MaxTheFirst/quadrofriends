# Backend API для «Квадро Друзья»

Спецификация целевого REST API и WebSocket-канала для текущего iOS-приложения. Сейчас экраны маршрутов, карты, чатов и чужих профилей в основном работают на `MockData` и локальном состоянии; описанные ниже ручки ещё не реализованы. Контракт покрывает существующие экраны и действия, необходимые для их полноценной работы. Публичный REST API версионируется: `https://api.quadro.friends/v1`.

## 1. Общие правила контракта

- JSON: `Content-Type: application/json; charset=utf-8`, имена полей `snake_case`. `PATCH` использует `application/merge-patch+json`; отсутствующее поле не меняется, `null` очищает nullable-поле. Для массивов `PATCH` заменяет весь массив; элементы коллекций по возможности меняются через дочерние ресурсы.
- Идентификаторы — непрозрачные строки UUID. Время — ISO 8601 UTC (`2026-10-18T12:30:00Z`), расстояние — метры, длительность — секунды, координаты — WGS84 `{ "lat": number, "lon": number }`. Сервер вычисляет расстояние, длительность и агрегаты; клиент не присылает готовый рейтинг или число прохождений.
- Все списки возвращают `{ "items": [...], "next_cursor": string | null }`. Параметры `limit` (по умолчанию 20, максимум 100) и `cursor` действуют совместно с фильтрами; порядок детерминированный. Пустой список — `items: []`. `total` не обязателен: если нужен счётчик, он указан отдельно в DTO.
- `GET` не меняет данные. `POST` создаёт ресурс, `PUT` создаёт или полностью заменяет адресуемый ресурс, `PATCH` частично меняет, `DELETE` удаляет. Успешный `POST` отвечает `201 Created` с `Location` и созданным DTO, `GET/PUT/PATCH` — `200`, `DELETE` — `204`. Исключения указаны у ручек. У всех деталей есть `ETag`; изменения поддерживают `If-Match` и отвечают `412`, если версия устарела.
- Все ручки, кроме `POST /sessions` и чтения публичных маршрутов (`GET /routes`, `GET /routes/{id}`, их геометрии, меток и отзывов), требуют `Authorization: Bearer <access_token>`. Создание следующей сессии авторизуется действительным refresh token прежней сессии. Запросы с приватной ссылкой дополнительно передают `X-Route-Link-Token: <token>`; токен не следует помещать в аналитические логи. Демо-режим остаётся локальным: читать публичные данные можно без сессии, запись и приватные данные требуют входа.
- Повторяемые операции `POST` (создание сессии, маршрута, записи, сообщения, медиа, голосового вложения, чата и позиции) принимают `Idempotency-Key: <UUID>`: повтор того же запроса возвращает тот же результат, повтор с другим телом — `409`. Для остальных ресурсов ключ хранится не менее 24 часов; для сессии достаточно 5 минут. При обновлении сессии ключ обязателен, чтобы сетевой повтор не выглядел повторным использованием уже ротированного refresh token.
- Поиск и фильтры кодируются query-параметрами, а не путями вида `/search`. Удаление чужих данных и получение чужих приватных маршрутов запрещены независимо от того, скрыта ли кнопка в UI.

### Единая ошибка

```json
{
  "error": {
    "code": "validation_error",
    "message": "Название обязательно",
    "details": [{ "field": "title", "code": "required" }],
    "request_id": "req_01J..."
  }
}
```

Коды HTTP: `400` — неверный запрос/координаты/курсор; `401` — нет или истёк токен; `403` — нет прав; `404` — ресурс не найден или приватный ресурс скрыт; `409` — конфликт уникальности/состояния; `412` — устаревший `ETag`; `413` — слишком большое медиа; `415` — неверный MIME; `416` — неверный диапазон байтов аудио; `422` — корректный JSON с недопустимыми значениями; `429` — превышен лимит (`Retry-After`); `5xx` — ошибка сервера. Стабильные `error.code`: `invalid_token`, `expired_token`, `forbidden`, `not_found`, `validation_error`, `username_taken`, `invalid_state`, `conflict`, `media_not_ready`, `rate_limited`.

## 2. Аутентификация и аккаунт

Приложение использует VK ID SDK. После входа iOS передаёт серверу полученный от VK краткоживущий токен; сервер проверяет его через VK ID, привязку к нашему VK-приложению и срок действия, затем выдаёт собственную сессию. Клиент не должен считать факт входа в VK подтверждением доступа к backend. Секрет VK-приложения должен храниться только на сервере; текущую конфигурацию `VK_CLIENT_SECRET` в `Info.plist` нужно пересмотреть при подключении production backend. Приложение хранит собственный refresh token в Keychain, сервер — его хеш и ротацию.

| Метод и путь | Назначение | Тело → ответ |
|---|---|---|
| `POST /sessions` | Вход/регистрация через VK или создание следующей сессии по refresh token | `CreateSessionRequest` → `SessionDTO`, `201` |
| `DELETE /sessions/{session_id}` | Выход с текущего устройства, отзыв refresh token | нет → `204` |
| `GET /users/me` | Свой профиль после входа | нет → `UserDetailDTO` |
| `DELETE /users/me` | Удаление аккаунта и отзыв всех сессий | нет → `204`; политика хранения/удаления связанных данных определяется сервером |

```ts
type CreateSessionRequest =
  | { grant_type: "vk"; provider_access_token: string; device_id?: string }
  | { grant_type: "refresh"; refresh_token: string; device_id?: string };
type SessionDTO = {
  id: string;
  access_token: string;
  access_expires_at: string;
  refresh_token: string;         // одноразовый: предыдущий аннулируется
  refresh_expires_at: string;
  user: UserDetailDTO;
  is_new_user: boolean;
};
```

Первый вход создаёт профиль с доступными данными VK и требует от пользователя заполнить обязательные поля профиля, если VK их не вернул. При повторном входе по тому же VK ID создаётся новая сессия существующего пользователя. Запрос с `grant_type=refresh` создаёт новую сессию и атомарно отзывает прежнюю; повторное использование старого refresh token с другим `Idempotency-Key` отзывает семейство токенов. `device_id` — случайный ID установки, не рекламный ID. `DELETE /sessions/{id}` доступен только владельцу сессии.

## 3. Пользователи, подписки и техника

| Метод и путь | Назначение | Тело → ответ |
|---|---|---|
| `GET /users?query=&limit=&cursor=` | Поиск по имени и `username`: выбор получателя сообщения и доступа к маршруту | нет → список `UserSummaryDTO` |
| `GET /users/{user_id}` | Чужой публичный профиль со статистикой и техникой | нет → `UserDetailDTO` |
| `PATCH /users/me` | Имя, фамилия, username, год рождения, город, аватар | `UpdateProfileRequest` → `UserDetailDTO` |
| `GET /users/{user_id}/routes?limit=&cursor=` | Публичные маршруты пользователя | нет → список `RouteSummaryDTO` |
| `GET /users/{user_id}/followers?limit=&cursor=` | Подписчики | нет → список `UserSummaryDTO` |
| `GET /users/{user_id}/following?limit=&cursor=` | Подписки | нет → список `UserSummaryDTO` |
| `PUT /users/{user_id}/followers/me` | Подписаться, повтор безопасен | нет → `FollowDTO`, `200/201` |
| `DELETE /users/{user_id}/followers/me` | Отписаться | нет → `204` |
| `GET /users/me/vehicles` | Своя техника | нет → список `VehicleDTO` |
| `POST /users/me/vehicles` | Добавить квадроцикл | `VehicleWriteDTO` → `VehicleDTO` |
| `PATCH /users/me/vehicles/{vehicle_id}` | Изменить технику или сделать основной | поля `VehicleWriteDTO` → `VehicleDTO` |
| `DELETE /users/me/vehicles/{vehicle_id}` | Удалить технику | нет → `204` |

```ts
type UserSummaryDTO = {
  id: string; username: string; display_name: string;
  avatar: MediaDTO | null; city: string | null;
};
type UserDetailDTO = UserSummaryDTO & {
  first_name: string; last_name: string; birth_year: number | null;
  vehicles: VehicleDTO[];
  stats: { route_count: number; follower_count: number; following_count: number };
  is_following: boolean;       // для собственного профиля false
  profile_complete: boolean;
  created_at: string; updated_at: string;
};
type UpdateProfileRequest = {
  first_name?: string; last_name?: string; username?: string;
  birth_year?: number | null; city?: string | null; avatar_media_id?: string | null;
};
type VehicleWriteDTO = {
  model: string; year: number; image_media_id?: string | null; is_primary: boolean;
};
type VehicleDTO = VehicleWriteDTO & { id: string; image: MediaDTO | null; created_at: string; updated_at: string };
type FollowDTO = { user_id: string; follower_id: string; created_at: string };
```

`username`: 3–30 символов `[a-z0-9_]`, уникален без учёта регистра; `@` — только UI. При первом входе сервер может выдать временный уникальный username; если VK не вернул имя/фамилию, до заполнения профиля они пустые и `profile_complete=false`. Публикация маршрута, сообщение и подписка требуют завершённого профиля. После заполнения имя и фамилия обязательны, 1–80 символов; `birth_year` — `1900..текущий год`, `city` — до 120 символов. Модель техники 1–120 символов, год `1950..(текущий год + 1)`. У пользователя не более одного основного транспортного средства; установка `is_primary=true` атомарно снимает признак с остальных. Если удалён основной и другие остались, сервер назначает первый по `created_at`. Подписаться на себя нельзя (`422`). Чужой профиль показывает только разрешённые публичные данные.

## 4. Медиа

Локальные `imageName` из Swift-моделей — названия ресурсов в приложении, не данные backend. Пользовательские фото и аватары хранятся как медиа-ресурсы. Для текущего масштаба достаточно загрузки через API; сервер удаляет EXIF с GPS и отдаёт изображения через CDN/подписанные HTTPS URL.

| Метод и путь | Назначение | Тело → ответ |
|---|---|---|
| `POST /media` | Загрузить фото для аватара, техники, маршрута, метки или сообщения | `multipart/form-data` с `file` → `MediaDTO`, `201` |
| `GET /media/{media_id}` | Метаданные вложения, если есть право на связанный объект | нет → `MediaDTO` |
| `DELETE /media/{media_id}` | Удалить ещё не привязанную загрузку владельца | нет → `204` |

```ts
type MediaDTO = {
  id: string; mime_type: "image/jpeg" | "image/png" | "image/heic";
  width: number; height: number; byte_size: number;
  url: string; thumbnail_url: string; created_at: string;
};
```

Максимум 20 МБ на фото, 10 фото у метки, 20 у маршрута, 10 в одном сообщении. URL может истекать: клиент обновляет DTO через ресурс-владелец. Сервер проверяет фактический формат файла, сканирует загрузку и создаёт превью. При ссылке на `media_id` проверяются владелец загрузки и готовность обработки. Для приватных маршрутов и чатов URL доступны только авторизованному читателю либо имеют короткую подпись.

### Голосовые вложения

Для аудио нужен отдельный ресурс: у него есть длительность, свой формат, проверка доступа к чату и выдача файла с `Range` для воспроизведения и перемотки. `POST /media` выше остаётся загрузкой изображений. Создание голосового сообщения выполняется в два шага: сначала файл, затем JSON-сообщение со ссылкой на готовое вложение. Так сетевой повтор отправки сообщения не загружает файл повторно.

| Метод и путь | Назначение | Тело → ответ |
|---|---|---|
| `POST /voice-attachments` | Загрузить записанный звук | `multipart/form-data` с `file` → `VoiceAttachmentDTO`, `201` |
| `GET /voice-attachments/{attachment_id}` | Получить метаданные и длительность, проверить доступ | нет → `VoiceAttachmentDTO` |
| `GET /voice-attachments/{attachment_id}/content` | Скачать или потоково воспроизвести звук | нет → `audio/mp4`, `200`; с `Range` → `206 Partial Content` |
| `DELETE /voice-attachments/{attachment_id}` | Удалить своё ещё не отправленное вложение | нет → `204` |

```ts
type VoiceAttachmentDTO = {
  id: string;
  mime_type: "audio/mp4"; // файл .m4a, AAC-LC
  duration_ms: number;     // длительность определяет сервер по файлу
  byte_size: number;
  waveform?: number[];    // нормализованные значения 0..1 для UI, если рассчитаны
  created_at: string;
};
```

Принимается один файл `.m4a`/AAC-LC длительностью 1–180 секунд и размером до 10 МБ. Сервер проверяет фактический контейнер, кодек и длительность, не доверяя MIME и метаданным клиента. Ответ загрузки означает, что файл готов к чтению; неготовое вложение нельзя привязать к сообщению. Одно вложение привязывается ровно к одному голосовому сообщению и одному чату; непривязанные файлы удаляются через 24 часа. До отправки читать файл может только загрузивший пользователь; после отправки — текущие участники чата. При удалении сообщения доступ к файлу прекращается, физическое удаление можно выполнить позже.

`GET .../content` проверяет bearer token и участие в чате, возвращает `Content-Type: audio/mp4`, `Content-Length`, `Accept-Ranges: bytes`, `ETag`, `Cache-Control: private, no-store`. Запрос `Range: bytes=0-65535` возвращает `206` и `Content-Range`; неверный диапазон — `416`. Это же `GET` используется для полного скачивания в локальный временный файл. Клиент должен удалять временную копию при выходе из аккаунта. Публичный постоянный URL на голосовое сообщение не выдаётся.

## 5. Маршруты, поиск и карта

Карта (`MapKit`) и её стиль остаются на клиенте; backend отдаёт маршруты с координатами. `bbox` задаётся как `min_lon,min_lat,max_lon,max_lat`, пересечение считается по геометрии маршрута. `max_distance_m` ограничивает длину трека, а не расстояние от пользователя. На карте список может запрашиваться повторно при смене области и фильтров.

| Метод и путь | Назначение | Тело → ответ |
|---|---|---|
| `GET /routes` | Каталог, поиск, рекомендуемые и новые маршруты | параметры ниже → список `RouteSummaryDTO` |
| `GET /routes/{route_id}` | Карточка маршрута, автор, рейтинг, доступ | нет → `RouteDetailDTO` |
| `POST /routes` | Создать маршрут вручную или из завершённой записи | `RouteCreateRequest` → `RouteDetailDTO` |
| `PATCH /routes/{route_id}` | Редактировать свои название, описание, теги, фото, видимость | `RoutePatchRequest` → `RouteDetailDTO` |
| `DELETE /routes/{route_id}` | Удалить свой маршрут и связанные доступы | нет → `204` |
| `GET /routes/{route_id}/geometry` | Полный упорядоченный трек для карты/ведения | нет → `RouteGeometryDTO` |
| `PUT /routes/{route_id}/geometry` | Полностью заменить трек своего маршрута после редактирования точек | `RouteGeometryWriteDTO` → `RouteGeometryDTO` |
| `GET /users/me/routes?visibility=&sort=&limit=&cursor=` | «Мои маршруты», `visibility=private` для приватной вкладки | нет → список `RouteSummaryDTO` |
| `GET /users/me/recent-routes?limit=&cursor=` | Недавно открытые доступные маршруты, если вкладка «Недавние» означает историю просмотра | нет → список `RouteSummaryDTO` |
| `PUT /users/me/recent-routes/{route_id}` | Зафиксировать открытие карточки, без дубликатов | нет → `RecentRouteDTO`, `200/201` |
| `GET /users/me/bookmarks?limit=&cursor=` | Сохранённые маршруты | нет → список `RouteSummaryDTO` |
| `PUT /users/me/bookmarks/{route_id}` | Сохранить маршрут | нет → `RouteBookmarkDTO`, `200/201` |
| `DELETE /users/me/bookmarks/{route_id}` | Убрать из сохранённых | нет → `204` |

Параметры `GET /routes`: `query` (название, описание, тег), `visibility=public|private|all` (`private` и `all` требуют входа и включают только свои/доступные приватные маршруты), `bbox`, `max_distance_m`, `max_duration_s`, `duration_bucket=up_to_4h|up_to_8h|full_day`, `min_difficulty`, `min_mud`, `min_fields`, `min_forest`, `min_scenery` (`0|3|4|4.5`), `min_completed_count`, `sort=newest|popular|rating|recommended`, `limit`, `cursor`. Все фильтры применяются одновременно. Для рекомендуемых допустим `sort=recommended`; алгоритм остаётся внутренним для сервера. По умолчанию выдаются публичные маршруты.

```ts
type CoordinateDTO = { lat: number; lon: number };
type RouteRatingsDTO = {
  difficulty: number | null; mud: number | null; fields: number | null;
  forest: number | null; scenery: number | null;
};
type RouteSummaryDTO = {
  id: string; title: string; cover: MediaDTO | null;
  distance_m: number; duration_s: number;
  rating: number | null; review_count: number; completed_count: number;
  ratings: RouteRatingsDTO; visibility: "public" | "private";
  tags: string[]; author: UserSummaryDTO;
  start_point: CoordinateDTO; bounds: { min_lat: number; min_lon: number; max_lat: number; max_lon: number };
  is_bookmarked: boolean; created_at: string; updated_at: string;
};
type RouteDetailDTO = RouteSummaryDTO & {
  description: string; photos: MediaDTO[]; marker_count: number;
  access: { can_view: boolean; can_edit: boolean; via_link: boolean };
};
type RouteCreateRequest = {
  title: string; description?: string; visibility: "public" | "private";
  tags?: string[]; photo_media_ids?: string[]; cover_media_id?: string | null;
  duration_s?: number;
  geometry?: RouteGeometryWriteDTO; recording_id?: string; // ровно один источник трека
};
type RoutePatchRequest = {
  title?: string; description?: string; visibility?: "public" | "private";
  tags?: string[]; photo_media_ids?: string[]; cover_media_id?: string | null;
  duration_s?: number;
};
type RouteGeometryWriteDTO = { points: CoordinateDTO[]; is_loop?: boolean };
type RouteGeometryDTO = RouteGeometryWriteDTO & {
  route_id: string; distance_m: number; start_point: CoordinateDTO;
  bounds: { min_lat: number; min_lon: number; max_lat: number; max_lon: number };
  updated_at: string;
};
type RecentRouteDTO = { route_id: string; viewed_at: string };
type RouteBookmarkDTO = { route_id: string; user_id: string; created_at: string };
```

Правила: название 1–120 символов, описание до 10 000, до 10 тегов по 1–40; трек содержит 2–20 000 точек в допустимых широтах/долготах. Сервер пересчитывает метры и bounds при изменении геометрии. Длительность маршрута берётся из записи либо редактируемого поля `duration_s` (при ручном создании его нужно добавить в форму); значение больше нуля. Закрытие кольца задаётся `is_loop`, первую точку повторять в `points` не нужно. Поле `rating` — среднее оценок, `ratings` — средние по критериям, при отсутствии оценок — `null`; UI должен показывать «Нет оценок», а не нули. При смене `public → private` каталог сразу перестаёт выдавать маршрут.

## 6. Метки маршрута и отзывы

Метки имеют свои координаты и фото; расстояние от старта рассчитывается сервером вдоль трека. Владелец маршрута может менять опубликованные метки. Метки, добавленные во время личной записи, относятся к записи до сохранения её как маршрута.

| Метод и путь | Назначение | Тело → ответ |
|---|---|---|
| `GET /routes/{route_id}/markers?limit=&cursor=` | Список меток маршрута | нет → список `RouteMarkerDTO` |
| `GET /routes/{route_id}/markers/{marker_id}` | Экран метки | нет → `RouteMarkerDTO` |
| `POST /routes/{route_id}/markers` | Добавить метку к своему маршруту | `MarkerWriteDTO` → `RouteMarkerDTO` |
| `PATCH /routes/{route_id}/markers/{marker_id}` | Изменить название, описание, координаты, фото | поля `MarkerWriteDTO` → `RouteMarkerDTO` |
| `DELETE /routes/{route_id}/markers/{marker_id}` | Удалить метку | нет → `204` |
| `GET /routes/{route_id}/reviews?limit=&cursor=` | Отзывы и оценки | нет → список `RouteReviewDTO` |
| `PUT /routes/{route_id}/reviews/me` | Создать или заменить свою оценку, одну на пользователя | `RouteReviewWriteDTO` → `RouteReviewDTO`, `200/201` |
| `DELETE /routes/{route_id}/reviews/me` | Удалить свою оценку | нет → `204` |

```ts
type MarkerWriteDTO = {
  title: string; description?: string; coordinate: CoordinateDTO;
  photo_media_ids?: string[];
};
type RouteMarkerDTO = MarkerWriteDTO & {
  id: string; route_id: string; photos: MediaDTO[];
  distance_from_start_m: number; created_at: string; updated_at: string;
};
type RouteReviewWriteDTO = {
  difficulty: 1 | 2 | 3 | 4 | 5; mud: 1 | 2 | 3 | 4 | 5;
  fields: 1 | 2 | 3 | 4 | 5; forest: 1 | 2 | 3 | 4 | 5;
  scenery: 1 | 2 | 3 | 4 | 5; text?: string;
};
type RouteReviewDTO = RouteReviewWriteDTO & {
  id: string; route_id: string; author: UserSummaryDTO;
  created_at: string; updated_at: string;
};
```

Название метки 1–120 символов, описание до 5 000. Координата должна лежать рядом с треком (допуск сервера, например 500 м); для произвольной точки нужна отдельная сущность на карте. Оценку может оставить авторизованный пользователь, завершивший этот маршрут; автор не оценивает собственный маршрут. При пересчёте среднего оценка маршрута в карточке считается из пяти критериев каждого отзыва. Текущий UI только показывает рейтинг и отзывы; форму оценки надо добавить для появления новых данных.

## 7. Запись поездки и геопозиция

Запись — отдельный ресурс с состоянием. Режим `free` создаёт новый трек; `follow_route` запускает существующий маршрут. iOS получает координаты через Core Location, хранит очередь точек локально при потере сети и отправляет их пачками. Завершённая свободная запись может стать маршрутом через `POST /routes` с `recording_id`. У завершённого следования `completed_count` увеличивается один раз после валидации минимально пройденного трека, а не при простом нажатии «Старт».

| Метод и путь | Назначение | Тело → ответ |
|---|---|---|
| `POST /recordings` | Начать запись/ведение | `RecordingCreateRequest` → `RecordingDTO` |
| `GET /recordings/{recording_id}` | Восстановить активную запись после перезапуска | нет → `RecordingDTO` |
| `GET /users/me/recordings?status=&limit=&cursor=` | История своих записей | нет → список `RecordingDTO` |
| `POST /recordings/{recording_id}/track-points` | Добавить упорядоченную пачку GPS-точек | `TrackPointBatchRequest` → `TrackPointBatchResultDTO`, `201` |
| `GET /recordings/{recording_id}/track-points?cursor=&limit=` | Восстановить записанный трек | нет → список `TrackPointDTO` |
| `PATCH /recordings/{recording_id}` | Пауза, продолжение или завершение (`status`) | `{ "status": ... }` → `RecordingDTO` |
| `DELETE /recordings/{recording_id}` | Удалить незапубликованную свою запись | нет → `204` |
| `GET /recordings/{recording_id}/markers` | Черновые метки поездки | нет → список `RecordingMarkerDTO` |
| `POST /recordings/{recording_id}/markers` | Добавить метку во время записи | `MarkerWriteDTO` → `RecordingMarkerDTO` |
| `PATCH /recordings/{recording_id}/markers/{marker_id}` | Исправить черновую метку | поля `MarkerWriteDTO` → `RecordingMarkerDTO` |
| `DELETE /recordings/{recording_id}/markers/{marker_id}` | Удалить черновую метку | нет → `204` |

```ts
type RecordingCreateRequest = { mode: "free" | "follow_route"; route_id?: string };
type RecordingDTO = {
  id: string; owner_id: string; mode: "free" | "follow_route";
  route_id: string | null; status: "active" | "paused" | "finished";
  started_at: string; ended_at: string | null;
  distance_m: number; duration_s: number; point_count: number;
  marker_count: number; created_route_id: string | null;
};
type TrackPointDTO = {
  sequence: number; coordinate: CoordinateDTO; recorded_at: string;
  accuracy_m: number; altitude_m?: number | null; speed_mps?: number | null;
};
type TrackPointBatchRequest = { points: TrackPointDTO[] }; // 1–500 точек
type TrackPointBatchResultDTO = { accepted_count: number; last_sequence: number; recording: RecordingDTO };
type RecordingMarkerDTO = MarkerWriteDTO & {
  id: string; recording_id: string; photos: MediaDTO[]; created_at: string; updated_at: string;
};
```

`sequence` монотонно растёт с 1, уникален внутри записи. Повтор точки с тем же номером и содержимым безопасен; иной payload — `409`. Сервер отбрасывает точки с невозможной скоростью/точностью по согласованным порогам и сообщает об этом через `422` с номером точки. Допустимые переходы: `active ↔ paused`, `active|paused → finished`; из `finished` назад нельзя. Повторное завершение с тем же результатом безопасно. `follow_route` не даёт редактировать чужой опубликованный маршрут: его добавленные метки остаются личными метками записи. Для публикации чужих меток понадобится отдельный процесс предложения/модерации.

### Временная передача геопозиции

Фраза в экране старта о доступности геопозиции выбранным участникам и индикатор в чатах требуют явного управления доступом. Сервер никогда не публикует текущую позицию всем подписчикам автоматически.

| Метод и путь | Назначение | Тело → ответ |
|---|---|---|
| `POST /location-shares` | Начать передачу позиции выбранным пользователям и/или чату | `LocationShareCreateRequest` → `LocationShareDTO` |
| `GET /users/me/location-shares` | Свои активные передачи | нет → список `LocationShareDTO` |
| `GET /location-shares/{share_id}` | Статус и последняя позиция для участника | нет → `LocationShareDTO` |
| `POST /location-shares/{share_id}/positions` | Передать новую позицию | `LocationPositionWriteDTO` → `LocationPositionDTO` |
| `DELETE /location-shares/{share_id}` | Немедленно прекратить передачу | нет → `204` |
| `GET /chats/{chat_id}/location-shares?limit=&cursor=` | Активные передачи участников данного чата для плашки над сообщениями и карты чата | нет → список `VisibleLocationShareDTO` |
| `GET /users/me/visible-location-shares?bbox=&limit=&cursor=` | Все активные передачи, доступные пользователю через его чаты или прямой доступ, для основной карты | нет → список `VisibleLocationShareDTO` |

```ts
type LocationShareCreateRequest = {
  recording_id?: string | null; recipient_user_ids?: string[]; chat_ids?: string[];
  expires_at: string; // не дальше 24 ч от старта
};
type LocationPositionWriteDTO = { coordinate: CoordinateDTO; accuracy_m: number; recorded_at: string };
type LocationPositionDTO = LocationPositionWriteDTO & { received_at: string };
type LocationShareDTO = {
  id: string; owner: UserSummaryDTO; recording_id: string | null;
  recipient_user_ids: string[]; chat_ids: string[];
  status: "active" | "expired" | "stopped";
  last_position: LocationPositionDTO | null;
  created_at: string; expires_at: string;
};
type VisibleLocationShareDTO = {
  id: string; owner: UserSummaryDTO; chat_ids: string[]; // только доступные запросившему чаты
  last_position: LocationPositionDTO; created_at: string; expires_at: string;
};
```

Получать позицию могут только явно выбранные получатели и текущие участники выбранных чатов. При выходе из чата доступ отзывается. По истечении срока, окончании записи или `DELETE` новые позиции не принимаются. Историю точного перемещения получателям не отдавать: только последнюю позицию, с коротким сроком хранения. Чатовый `shares_location` вычисляется по активным доступным передачам.

Передача из чата начинается только после явного предупреждения и разрешения iOS на геолокацию: `POST /location-shares` с `chat_ids: [chat_id]` и `expires_at` (клиент по умолчанию выбирает 1 час). Клиент отправляет точки через `POST /location-shares/{id}/positions`, пока передача активна. Создатель останавливает её через `DELETE`; сервер сразу убирает точку из обоих списков и рассылает событие WebSocket. Оба новых `GET` возвращают только действующие передачи с актуальной позицией; записи без первой точки не показываются. `bbox` — необязательная граница карты в формате `min_lon,min_lat,max_lon,max_lat`; без неё возвращаются все доступные точки. В списке для карты одна передача встречается один раз, даже если пользователь состоит в нескольких указанных чатах. Сервер проверяет членство при каждом чтении и отправке WebSocket-события, не раскрывает получателям `recipient_user_ids` и точку после остановки или истечения срока. Состояние собственного доступа для отправителя определяется по `owner.id`.

## 8. Папки, закладки и доступ к приватным маршрутам

| Метод и путь | Назначение | Тело → ответ |
|---|---|---|
| `GET /users/me/folders?limit=&cursor=` | Мои папки со счётчиком маршрутов | нет → список `RouteFolderDTO` |
| `POST /users/me/folders` | Создать папку | `{ "name": string }` → `RouteFolderDTO` |
| `GET /users/me/folders/{folder_id}` | Папка и её метаданные | нет → `RouteFolderDTO` |
| `PATCH /users/me/folders/{folder_id}` | Переименовать | `{ "name": string }` → `RouteFolderDTO` |
| `DELETE /users/me/folders/{folder_id}` | Удалить папку, сами маршруты остаются | нет → `204` |
| `GET /users/me/folders/{folder_id}/routes?limit=&cursor=` | Содержимое папки | нет → список `RouteSummaryDTO` |
| `PUT /users/me/folders/{folder_id}/routes/{route_id}` | Добавить доступный маршрут | нет → `FolderRouteDTO`, `200/201` |
| `DELETE /users/me/folders/{folder_id}/routes/{route_id}` | Убрать маршрут из папки | нет → `204` |
| `GET /routes/{route_id}/access-grants` | Явный доступ пользователей, только владелец | нет → список `RouteAccessGrantDTO` |
| `PUT /routes/{route_id}/access-grants/{user_id}` | Дать доступ пользователю | нет → `RouteAccessGrantDTO`, `200/201` |
| `DELETE /routes/{route_id}/access-grants/{user_id}` | Отозвать доступ | нет → `204` |
| `GET /routes/{route_id}/link` | Текущая ссылка, только владелец | нет → `RouteLinkDTO` или `404` |
| `PUT /routes/{route_id}/link` | Включить доступ по ссылке, безопасно при повторе | нет → `RouteLinkDTO`, `200/201` |
| `DELETE /routes/{route_id}/link` | Выключить ссылку и аннулировать токен | нет → `204` |
| `GET /route-links/{token}` | Открыть ссылку после входа в приложение | нет → `RouteDetailDTO` |

```ts
type RouteFolderDTO = { id: string; name: string; route_count: number; created_at: string; updated_at: string };
type FolderRouteDTO = { folder_id: string; route_id: string; added_at: string };
type RouteAccessGrantDTO = { route_id: string; user: UserSummaryDTO; created_at: string };
type RouteLinkDTO = { route_id: string; url: string; token: string; created_at: string };
```

Папка принадлежит одному пользователю, имя 1–80 символов. В папку можно добавить свой, публичный или доступный приватный маршрут; после отзыва доступа недоступный маршрут скрывается из содержимого. Приватный маршрут видят владелец, пользователи из `access-grants` и вошедший пользователь с действительным токеном ссылки. Для запросов `GET /routes/{id}/geometry`, `.../markers` и старта `follow_route` по ссылке клиент передаёт `X-Route-Link-Token`. `GET /route-links/{token}` не раскрывает данные без авторизации; сервер проверяет токен через его хеш. После выключения ссылки прежний URL перестаёт работать, повторное включение создаёт новый токен. Экран «Поделиться» обязан сохранять переключатель и выбранных пользователей через эти ручки, а системный Share Sheet получает `url` из `RouteLinkDTO`.

## 9. Чаты и сообщения

Список и история чатов, личный/групповой чат, создание группы, поиск пользователя, текст, фото, голос, маршрут и геопозиция. Все сообщения создаются через REST; открытое приложение получает события чатов и геопозиции по одному WebSocket-соединению. Push нужен для закрытого приложения.

| Метод и путь | Назначение | Тело → ответ |
|---|---|---|
| `GET /chats?query=&limit=&cursor=` | Список чатов, поиск по названию/участникам/тексту последних сообщений | нет → список `ChatSummaryDTO` |
| `POST /chats` | Создать личный или групповой чат | `ChatCreateRequest` → `ChatDetailDTO`; для существующего личного чата вернуть его с `200` |
| `GET /chats/{chat_id}` | Заголовок, участники, права | нет → `ChatDetailDTO` |
| `PATCH /chats/{chat_id}` | Название/фото группы (администратор) | `{ "title"?, "avatar_media_id"? }` → `ChatDetailDTO` |
| `GET /chats/{chat_id}/members` | Участники | нет → список `ChatMemberDTO` |
| `PUT /chats/{chat_id}/members/{user_id}` | Добавить участника группы (администратор) | нет → `ChatMemberDTO`, `200/201` |
| `DELETE /chats/{chat_id}/members/{user_id}` | Исключить участника или выйти самому | нет → `204` |
| `GET /chats/{chat_id}/messages?limit=&cursor=` | История от новых к старым | нет → список `MessageDTO` |
| `POST /chats/{chat_id}/messages` | Отправить сообщение | `MessageCreateRequest` → `MessageDTO` |
| `DELETE /chats/{chat_id}/messages/{message_id}` | Удалить своё сообщение для всех | нет → `204` |
| `PUT /chats/{chat_id}/read-state` | Отметить прочитанным до конкретного сообщения | `{ "last_read_message_id": string }` → `ChatReadStateDTO` |
| `PUT /users/me/device-tokens/{device_id}` | Зарегистрировать APNs-токен устройства | `DeviceTokenWriteDTO` → `200/201` |
| `DELETE /users/me/device-tokens/{device_id}` | Удалить токен при выходе | нет → `204` |

```ts
type ChatCreateRequest = {
  kind: "direct" | "group"; participant_user_ids: string[];
  title?: string; avatar_media_id?: string | null;
};
type ChatMemberDTO = { user: UserSummaryDTO; role: "owner" | "admin" | "member"; joined_at: string };
type ChatSummaryDTO = {
  id: string; kind: "direct" | "group"; title: string; avatar: MediaDTO | null;
  last_message: MessageDTO | null; unread_count: number; shares_location: boolean;
  updated_at: string;
};
type ChatDetailDTO = ChatSummaryDTO & { members: ChatMemberDTO[]; can_manage_members: boolean; created_at: string };
type MessageCreateRequest =
  | { type: "text"; text: string }
  | { type: "photo"; media_ids: string[]; text?: string }
  | { type: "voice"; voice_attachment_id: string }
  | { type: "route"; route_id: string; text?: string }
  | { type: "location"; coordinate: CoordinateDTO; label?: string; text?: string }
  | { type: "live_location"; location_share_id: string; text?: string };
type MessageDTO = {
  id: string; chat_id: string; sender: UserSummaryDTO;
  type: "text" | "photo" | "voice" | "route" | "location" | "live_location";
  text: string | null; media: MediaDTO[]; route: RouteSummaryDTO | null;
  voice: VoiceAttachmentDTO | null;
  coordinate: CoordinateDTO | null; label: string | null;
  location_share_id: string | null;
  delivery_status: "sent" | "read" | null; // только для своих сообщений
  created_at: string; edited_at: string | null; deleted_at: string | null;
};
type ChatReadStateDTO = { chat_id: string; user_id: string; last_read_message_id: string; read_at: string };
type DeviceTokenWriteDTO = { platform: "ios"; apns_token: string; environment: "sandbox" | "production" };
```

Один личный чат на неупорядоченную пару пользователей, группа — от 3 участников включая создателя. У текста 1–4 000 символов. Отправитель, `created_at`, непрочитанное и статус доставки вычисляются сервером; клиент может сопоставить отправку через `Idempotency-Key`. `PUT /read-state` не может переместить указатель назад. Фото и маршрут в сообщении проверяются на право чтения каждого участника: отправка приватного маршрута не даёт доступ сама по себе; перед отправкой нужно добавить адресатов в `access-grants` либо включить ссылку. Статичная геопозиция (`location`) сохраняется в истории; `live_location` ссылается на действующую передачу и перестаёт показывать координаты после её окончания. Push содержит минимум данных и не раскрывает содержимое приватного сообщения или координаты на заблокированном экране без настройки пользователя.

Голосовое сообщение: iOS записывает `.m4a`, вызывает `POST /voice-attachments`, затем `POST /chats/{chat_id}/messages` с `{ "type": "voice", "voice_attachment_id": "..." }` и отдельным `Idempotency-Key`. Сервер атомарно связывает вложение с сообщением, проверяя владельца загрузки и участие в чате; повторная привязка к другому сообщению отвечает `409`. Получатель получает `VoiceAttachmentDTO` в `MessageDTO`, затем вызывает `GET /voice-attachments/{id}/content` для воспроизведения или скачивания. Удаление сообщения отзывает доступ к звуку. В iOS для этого нужны экран записи/проигрывания и разрешение микрофона; сейчас кнопка с иконкой микрофона не отправляет голосовые сообщения.

### События в реальном времени: WebSocket

`wss://api.quadro.friends/v1/realtime` — одно соединение на авторизованное приложение в активном состоянии, а не отдельный сокет на каждый чат или маршрут. При WebSocket handshake клиент передаёт `Authorization: Bearer <access_token>`; сервер проверяет токен и автоматически подписывает соединение на чаты пользователя и доступные ему передачи геопозиции. Срок действия access token истёк — сервер закрывает соединение, клиент обновляет сессию и подключается снова. Соединение использует TLS и ping/pong примерно раз в 30 секунд.

Сохранение сообщений, отметки прочтения, создание/остановка передачи и отправка позиции остаются HTTP-операциями из разделов выше. После успешной записи сервер публикует WebSocket-событие. Это сохраняет однозначный результат операции (`201/200`, `Idempotency-Key`) и позволяет клиенту повторить HTTP-запрос после потери сети. WebSocket нужен для быстрой доставки изменений другим устройствам; позже через него можно добавить временные события набора текста, не меняя REST-ресурсы.

```ts
type RealtimeEvent = {
  event_id: string;          // уникален, клиент устраняет дубликаты
  type:
    | "chat.message.created"
    | "chat.message.deleted"
    | "chat.updated"
    | "chat.read_state.updated"
    | "location.share.started"
    | "location.position.updated"
    | "location.share.stopped";
  occurred_at: string;
  data: MessageDTO | ChatSummaryDTO | ChatReadStateDTO |
    VisibleLocationShareDTO | { chat_id: string; message_id: string } |
    { share_id: string };
};
```

Для `location.position.updated` сервер отправляет только актуальный `VisibleLocationShareDTO`, не историю трека и не список приватных адресатов. Позиции ограничиваются по частоте (например, не чаще одного обновления в 5 секунд на передачу). При удалении участника из чата или отзыве доступа сервер немедленно прекращает события для него; каждое событие проверяется по текущим правам. События могут быть доставлены повторно или пропущены при разрыве соединения, поэтому после подключения/переподключения клиент заново читает `GET /chats`, страницы сообщений открытого чата до уже известного сообщения и списки видимых геопозиций. События, пришедшие во время этой синхронизации, буферизуются, затем применяются по ID ресурсов без дубликатов. Подключение повторяется с возрастающей задержкой до 30 секунд.

В фоне iOS не должен полагаться на постоянно открытый WebSocket: новые сообщения приходят через APNs, при открытии приложения выполняется REST-синхронизация. Если пользователь разрешил фоновую геолокацию, устройство может продолжать отправлять позиции через HTTP в рамках правил iOS; при отсутствии такой возможности передача завершается или истекает по `expires_at`. Частые GPS-точки для сохранённого трека продолжают идти через пакетный `POST /recordings/{id}/track-points` и локальную очередь.

## 10. Пример полного сценария

1. VK ID возвращает токен → `POST /sessions` → клиент кладёт токены в Keychain.
2. Карта запрашивает `GET /routes?bbox=...&sort=recommended`; выбор карточки — `GET /routes/{id}`, `GET /routes/{id}/geometry`, `GET /routes/{id}/markers`.
3. «Начать запись» → `POST /recordings` с `mode=free`; координаты пачками в `POST /recordings/{id}/track-points`; метки — в дочернюю коллекцию. Остановка — `PATCH /recordings/{id}` со `status=finished`.
4. «Сохранить маршрут» → `POST /routes` с `recording_id`, названием, описанием, фотографиями и видимостью. Сервер переносит трек и метки атомарно, сохраняет `created_route_id` в записи.
5. «Поделиться» → `PUT /routes/{id}/link`, нужные `PUT /routes/{id}/access-grants/{user_id}`; система отправляет полученный URL.
6. «Написать» в чужом профиле → `POST /chats` с `kind=direct`, затем `POST /chats/{id}/messages`; открытое приложение получает уведомление через `wss://api.quadro.friends/v1/realtime`.

## 11. Что требуется изменить в iOS при интеграции

- Заменить `MockData.routes`, `MockData.chats`, тестовые профили и локальный `ProfileStore` сетевыми репозиториями, кэшем и состояниями загрузки/ошибки; при первом входе синхронизировать профиль с сервером.
- В `TrailRoute` заменить `imageName`, строковые `duration` и фиксированные координаты на `MediaDTO`, `duration_s` и геометрию; в `ChatMessage` заменить локальный `UUID()` и строковое время на серверные ID/временные метки.
- Подключить фактическую геолокацию Core Location, разрешения, фоновую запись, локальную очередь точек и восстановление активной записи. Текущая карта показывает зашитую позицию пользователя и демонстрационный трек.
- Подключить загрузку фото и сохранение результата кнопок, которые сейчас являются заглушками: создание/редактирование маршрута и папок, новые чаты/группы, подписка, сообщение автору, закладка, ссылка и доступ, фото в чате.
- Добавить запись голоса через `AVAudioRecorder`, разрешение `NSMicrophoneUsageDescription`, загрузку `.m4a` и воспроизведение скачанного аудио; текущая иконка микрофона в чате не реализует запись.
- Открывать один WebSocket после входа и перехода приложения в активное состояние, закрывать в фоне/при выходе, после переподключения перечитывать чаты и доступные геопозиции через REST.
- Переключатель темы приложения и вид карты можно хранить локально: для них не нужны backend-ручки. Тайлы карты поставляет MapKit, не этот API.

## 12. Минимальные приёмочные проверки backend

1. Гость видит только публичные маршруты; приватный маршрут не находится поиском и отвечает `404` без доступа. Отозванная ссылка и доступ пользователя перестают работать сразу.
2. Дублированные запросы создания с одним `Idempotency-Key` не создают второй маршрут, запись, чат или сообщение. Повтор пачки GPS-точек не удваивает расстояние и прохождения.
3. Пользователь может менять только собственные профиль, технику, папки, маршрут и его метки; сообщения отправляет только участник чата.
4. Поиск на карте применяет все фильтры одновременно и возвращает координаты/geometry для каждого результата; курсор не пропускает и не дублирует элементы при стабильной выборке.
5. Токен VK, refresh rotation, выход и просроченная сессия проходят проверку; push/WebSocket не раскрывают данные после выхода из чата или отзыва доступа.
6. Остановка трансляции позиции или истечение срока немедленно скрывает координаты получателей; завершённое прохождение учитывается не более одного раза.
7. Голосовое вложение загружается один раз и привязывается к одному сообщению; участник чата получает `200` или `206` при чтении аудио, посторонний — `404`, удалённое сообщение отзывает доступ к файлу.
8. После обрыва WebSocket и переподключения клиент восстанавливает пропущенные сообщения и актуальные позиции через REST; бывший участник чата больше не получает события и не читает позицию.
