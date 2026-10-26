import SwiftUI
import OneRoofCore

/// 66 pt rail (steps 0 and 2).
struct PlaceRail: View {
    @Binding var place: Place
    var step: FocusStep
    var tokens: V2Planes
    var dock: V2Dock
    var onLook: () -> Void
    var body: some View {
        VStack(spacing: 3) {
            Color.clear.frame(height: 28) // traffic lights
            ForEach(Place.allCases) { p in
                Button { place = p } label: {
                    VStack(spacing: 2) {
                        Image(systemName: p.symbol).font(.system(size: 15))
                        Text(p.title).font(.system(size: 9.5, weight: p == place ? .semibold : .regular)).lineLimit(1)
                    }
                    .frame(width: 52).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(p == place ? tokens.surface : .clear).shadow(color: .black.opacity(p == place ? 0.12 : 0), radius: 1, y: 1))
                    .foregroundStyle(p == place ? tokens.text : tokens.text2)
                    .overlay(alignment: .topTrailing) { if p == .needsYou && dock.needsYou > 0 { NeedsBadge(count: dock.needsYou) } }
                }
                .buttonStyle(.plain).help(p.title)
            }
            Spacer()
            if step.seatsInRail {
                VStack(spacing: 5) {
                    ForEach(dock.seats.prefix(3)) { s in
                        ProgressView(value: s.used).tint(s.badge).frame(width: 30).opacity(s.off ? 0.45 : 1)
                    }
                    Text("seats").font(.system(size: 9)).foregroundStyle(tokens.text3)
                }.padding(.bottom, 8)
            }
            Button(action: onLook) { VStack(spacing: 2) { Image(systemName: "circle.lefthalf.filled").font(.system(size: 15)); Text("Look").font(.system(size: 9.5)) } }
                .buttonStyle(.plain).foregroundStyle(tokens.text2).padding(.bottom, 12)
        }
        .frame(width: 66).background(tokens.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(tokens.separatorStrong).frame(width: 1) }
    }
}

/// The places as a row of icons at the top of the session column (step 1).
struct PlacesIconRow: View {
    @Binding var place: Place
    var tokens: V2Planes
    var needsYou: Int
    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            ForEach(Place.allCases) { p in
                Button { place = p } label: {
                    Image(systemName: p.symbol).font(.system(size: 12)).frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7).fill(p == place ? tokens.surface : .clear))
                        .foregroundStyle(p == .needsYou && needsYou > 0 ? Color(.systemRed) : (p == place ? tokens.text : tokens.text2))
                }
                .buttonStyle(.plain).help(p.title)
            }
        }
        .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
    }
}

struct NeedsBadge: View {
    var count: Int
    var body: some View {
        Text("\(count)").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 4).background(Capsule().fill(Color(.systemRed))).offset(x: -2, y: 2)
    }
}
