import SwiftUI
import ClauWatchCore

struct PopoverView: View {
    let stats: SessionStats
    @State private var elapsed: Int = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            divider
            sessionSection
            divider
            cumulSection
            divider
            projectsSection
            divider
            footerRow
        }
        .frame(width: 288)
        .background(Color(hex: 0x171B26))
        .onReceive(ticker) { _ in if stats.activeSession != nil { elapsed += 1 } }
        .onAppear {
            elapsed = stats.activeSession.map {
                Int(Date().timeIntervalSince($0.startedAt))
            } ?? 0
        }
    }

    private var divider: some View {
        Rectangle().fill(Color(hex: 0x2A3042)).frame(height: 1)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0x6B7280))
            Text("ClauWatch")
                .font(.custom("PerpetuaMT", size: 14))
                .kerning(1.8)
                .foregroundColor(Color(hex: 0xF0F0F5))
            Spacer()
            if stats.activeSession != nil {
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: 0x34C759))
                        .frame(width: 5, height: 5)
                        .shadow(color: Color(hex: 0x34C759), radius: 3)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .medium))
                        .kerning(0.6)
                        .foregroundColor(Color(hex: 0x34C759))
                }
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            label("Session active")
            if let active = stats.activeSession {
                HStack {
                    Label(active.projectName, systemImage: "folder.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: 0xF0F0F5))
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 9))
                        Text(hms(elapsed))
                            .font(.system(size: 12, weight: .semibold).monospaced())
                            .monospacedDigit()
                    }
                    .foregroundColor(Color(hex: 0x34C759))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Color(hex: 0x34C759).opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: 0x34C759).opacity(0.22)))
                    .cornerRadius(6)
                }
            } else {
                Text("Aucune session active")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0x6B7280))
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
    }

    private var cumulSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            label("Temps cumulé")
            HStack(spacing: 6) {
                cell("Auj.",  icon: "sun.min",              value: stats.todayDuration, accent: true)
                cell("Sem.",  icon: "calendar.badge.clock", value: stats.weekDuration)
                cell("Mois",  icon: "calendar",             value: stats.monthDuration)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
    }

    private func cell(_ title: String, icon: String, value: Int, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                    .foregroundColor(Color(hex: 0x6B7280))
                Text(title).font(.system(size: 10))
                    .foregroundColor(Color(hex: 0x6B7280))
            }
            Text(hm(value))
                .font(.custom("PerpetuaMT", size: 17))
                .kerning(2.0)
                .foregroundColor(accent ? Color(hex: 0x34C759) : Color(hex: 0xF0F0F5))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("heures")
                .font(.system(size: 9)).kerning(0.9)
                .foregroundColor(Color(hex: 0x6B7280))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(Color(hex: 0x1E2436))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x2A3042)))
        .cornerRadius(8)
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            label("Projets · cette semaine")
            let maxDur = stats.projectsThisWeek.first?.duration ?? 1
            let activeName = stats.activeSession?.projectName
            ForEach(Array(stats.projectsThisWeek.prefix(4)), id: \.path) { proj in
                HStack(spacing: 6) {
                    Image(systemName: proj.name == activeName ? "folder.fill" : "folder")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: 0x6B7280))
                    Text(proj.name)
                        .font(.system(size: 11.5,
                            weight: proj.name == activeName ? .medium : .regular))
                        .foregroundColor(proj.name == activeName
                            ? Color(hex: 0xF0F0F5) : Color(hex: 0x8B95A8))
                        .lineLimit(1)
                    Spacer()
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x1E2436))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(proj.name == activeName
                                    ? Color(hex: 0x34C759) : Color(hex: 0x2A3042))
                                .frame(width: g.size.width * CGFloat(proj.duration)
                                    / CGFloat(maxDur))
                        }
                    }
                    .frame(width: 48, height: 2)
                    Text(hm(proj.duration))
                        .font(.system(size: 10.5, weight: .medium).monospaced())
                        .monospacedDigit()
                        .foregroundColor(proj.name == activeName
                            ? Color(hex: 0x34C759) : Color(hex: 0x6B7280))
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
    }

    private var footerRow: some View {
        HStack {
            Button(action: {}) {
                Label("Vue complète", systemImage: "square.grid.2x2")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x6B7280))
            }.buttonStyle(.plain)
            Spacer()
            Button(action: {}) {
                Label("Paramètres", systemImage: "gearshape")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x6B7280))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 15).padding(.vertical, 9)
        .background(Color(hex: 0x131720))
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium)).kerning(1.1)
            .foregroundColor(Color(hex: 0x6B7280))
    }

    private func hms(_ s: Int) -> String {
        String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private func hm(_ s: Int) -> String {
        String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
            red:     Double((hex >> 16) & 0xFF) / 255,
            green:   Double((hex >> 8)  & 0xFF) / 255,
            blue:    Double( hex        & 0xFF) / 255,
            opacity: alpha)
    }
}
