import SwiftUI

struct RoutePhoto: View {
    let imageName: String
    var height: CGFloat = 160
    var cornerRadius: CGFloat = 18

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct AvatarView: View {
    let imageName: String?
    let initials: String
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.brandOlive.opacity(0.16)
                    Text(initials)
                        .font(.headline)
                        .foregroundStyle(Color.brandOlive)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2))
        .accessibilityLabel("Аватар (initials)")
    }
}

struct RatingLabel: View {
    let rating: Double
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .foregroundStyle(Color.brandOrange)
            Text(rating, format: .number.precision(.fractionLength(1)))
                .fontWeight(.semibold)
            if let count {
                Text("(\(count))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Рейтинг (rating) из 5")
    }
}

struct RouteMeta: View {
    let route: TrailRoute

    var body: some View {
        HStack(spacing: 8) {
            Label("\(route.distance) км", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            Text("•")
            Label(route.duration, systemImage: "clock")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct TagPill: View {
    let text: String
    var selected = false

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(selected ? Color.brandOlive : Color.surfaceCream, in: Capsule())
            .foregroundStyle(selected ? Color.white : Color.primary)
    }
}

struct SectionTitle: View {
    let title: String
    var action: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            if let action {
                Text(action)
                    .font(.caption)
                    .foregroundStyle(Color.brandOlive)
            }
        }
    }
}

struct RouteRow: View {
    let route: TrailRoute

    var body: some View {
        HStack(spacing: 12) {
            Image(route.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 82, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(route.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                RouteMeta(route: route)
                RatingLabel(rating: route.rating)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.surfaceCream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct FilledActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.brandOlive.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EmptySelectionCircle: View {
    let selected: Bool

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(selected ? Color.brandOlive : Color.secondary)
            .font(.title3)
    }
}
