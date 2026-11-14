import SwiftUI

/// Small ring showing today's practice time against the daily goal.
struct DailyGoalRing: View {
    let practiced: TimeInterval
    let goalMinutes: Int

    var body: some View {
        let goal = TimeInterval(goalMinutes * 60)
        let progress = goal > 0 ? min(1, practiced / goal) : 0
        let done = progress >= 1
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(done ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                Text("\(Int(practiced / 60)) of \(goalMinutes) min")
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
        }
        .help("Daily goal. Drill typing time and races both count.")
    }
}
