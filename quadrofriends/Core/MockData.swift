import CoreLocation
import Foundation

enum MockData {
    static let alex = RouteAuthor(
        id: "alex",
        name: "Алексей Смирнов",
        username: "kvadro_life",
        birthYear: 1997,
        city: "Ленинградская область",
        avatarImage: "RouteForest",
        initials: "АС",
        vehicles: [Vehicle(model: "Yamaha Grizzly 700", year: 2020, imageName: "RouteForest", isPrimary: true)]
    )

    static let maria = RouteAuthor(
        id: "maria",
        name: "Мария Иванова",
        username: "mud_queen",
        birthYear: 1994,
        city: "Санкт-Петербург",
        avatarImage: "RouteMountain",
        initials: "МИ",
        vehicles: [Vehicle(model: "Polaris Sportsman 570", year: 2021, imageName: "RouteMountain", isPrimary: true)]
    )

    static let dmitry = RouteAuthor(
        id: "dmitry",
        name: "Дмитрий Орлов",
        username: "north_trail",
        birthYear: 1992,
        city: "Выборг",
        avatarImage: "RouteMud",
        initials: "ДО",
        vehicles: []
    )

    static let routes: [TrailRoute] = [
        TrailRoute(
            id: "forest-adventure",
            title: "Лесные приключения",
            imageName: "RouteForest",
            distance: 32,
            duration: "6 ч",
            rating: 4.7,
            reviewCount: 87,
            completedCount: 326,
            ratings: RouteRatings(difficulty: 4.7, mud: 4.9, fields: 4.2, forest: 4.8, scenery: 4.9),
            isPrivate: false,
            description: "Маршрут проходит через хвойные массивы, каменистые подъёмы и открытые поля. Подходит для райдеров с опытом.",
            tags: ["Лес", "Пейзажи", "Средняя сложность"],
            author: alex
        ),
        TrailRoute(
            id: "mud-weekend",
            title: "Покатушка выходного дня",
            imageName: "RouteMud",
            distance: 25,
            duration: "4 ч",
            rating: 4.3,
            reviewCount: 42,
            completedCount: 148,
            ratings: RouteRatings(difficulty: 3.8, mud: 4.9, fields: 3.1, forest: 4.2, scenery: 3.9),
            isPrivate: true,
            description: "Кольцевой маршрут недалеко от города: броды, колеи и много хорошей грязи.",
            tags: ["Грязь", "Брод", "Кольцевой"],
            author: dmitry
        ),
        TrailRoute(
            id: "mountain-paths",
            title: "Горные тропы",
            imageName: "RouteMountain",
            distance: 37,
            duration: "1 день",
            rating: 4.8,
            reviewCount: 196,
            completedCount: 512,
            ratings: RouteRatings(difficulty: 4.9, mud: 3.2, fields: 2.7, forest: 4.7, scenery: 5.0),
            isPrivate: false,
            description: "Панорамный маршрут по старым лесным дорогам с подъёмом к смотровой площадке.",
            tags: ["Горы", "Пейзажи", "Сложный"],
            author: maria
        ),
        TrailRoute(
            id: "fields-forest",
            title: "Поля и леса",
            imageName: "RouteFields",
            distance: 41,
            duration: "1 день",
            rating: 4.7,
            reviewCount: 73,
            completedCount: 241,
            ratings: RouteRatings(difficulty: 2.4, mud: 2.8, fields: 4.9, forest: 4.3, scenery: 4.6),
            isPrivate: false,
            description: "Спокойная поездка по полевым дорогам, берёзовым рощам и берегу озера.",
            tags: ["Поля", "Лес", "Лёгкий"],
            author: alex
        )
    ]

    static let folders: [RouteFolder] = [
        RouteFolder(name: "Любимые маршруты", count: 12, icon: "heart.fill"),
        RouteFolder(name: "На выходные", count: 5, icon: "sun.max.fill"),
        RouteFolder(name: "Покатушки 2026", count: 18, icon: "calendar")
    ]

    static let chats: [ChatPreview] = [
        ChatPreview(id: "band", title: "Квадро Банда", subtitle: "Иван: Кто на покатушку в эти выходные?", time: "09:15", unread: 2, avatarImage: "RouteForest", initials: "КБ"),
        ChatPreview(id: "wolves", title: "Лесные волки", subtitle: "Алексей отправил геопозицию", time: "09:02", unread: 3, avatarImage: "RouteFields", initials: "ЛВ"),
        ChatPreview(id: "rider", title: "@atv_rider", subtitle: "Привет! Когда следующая покатушка?", time: "Вчера", unread: 0, avatarImage: nil, initials: "АС"),
        ChatPreview(id: "maria", title: "Мария", subtitle: "Отличные фото с маршрута!", time: "Вчера", unread: 0, avatarImage: nil, initials: "МИ"),
        ChatPreview(id: "weekend", title: "Покатушка выходного дня", subtitle: "Вы: Посмотрите метку", time: "Пн", unread: 0, avatarImage: "RouteMud", initials: "ПВ"),
        ChatPreview(id: "dmitry", title: "Дмитрий", subtitle: "Я на месте", time: "Пн", unread: 0, avatarImage: nil, initials: "Д")
    ]

    static let chatMessages: [ChatMessage] = [
        ChatMessage(author: "Иван Петров", isMine: false, time: "09:15", kind: .text("Кто на покатушку в эти выходные?")),
        ChatMessage(author: "Вы", isMine: true, time: "09:17", kind: .text("Я в деле! Куда едем?")),
        ChatMessage(author: "Алексей Смирнов", isMine: false, time: "09:18", kind: .text("Вот координаты старта")),
        ChatMessage(
            author: "Алексей Смирнов",
            isMine: false,
            time: "09:18",
            kind: .location(CLLocationCoordinate2D(latitude: 59.980, longitude: 30.262))
        )
    ]
}
