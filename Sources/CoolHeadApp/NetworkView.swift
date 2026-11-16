import AppKit
import CoolHeadCore
import SwiftUI

/// "Test my network", shown in the panel's middle the way Report a problem is. Opening it reads what the Mac can say
/// about its connection (no prompt, about a second); Apple's test runs only when Start test is pressed, and stops if
/// the view is closed.
@MainActor
final class NetworkTester: ObservableObject {
    static let shared = NetworkTester()

    enum Phase: Equatable { case reading, ready, testing(started: Date), done(NetworkCheck.Outcome) }

    @Published var shown = false
    @Published private(set) var phase = Phase.reading
    @Published private(set) var setup: NetworkCheck.Setup?
    private var work: Task<Void, Never>?

    /// Opens the view and reads the connection; nothing is sent.
    func open() {
        shown = true
        phase = .reading
        work?.cancel()
        work = Task {
            let s = await Task.detached { NetworkCheck.readSetup() }.value
            guard !Task.isCancelled else { return }
            setup = s
            phase = .ready
        }
    }

    /// Runs Apple's test. Who was using the network is read again first, since the test itself fills it.
    func start() {
        work?.cancel()
        phase = .testing(started: Date())
        work = Task {
            let s = await Task.detached { NetworkCheck.readSetup() }.value
            guard !Task.isCancelled else { return }
            setup = s
            let outcome = await NetworkCheck.run()
            guard !Task.isCancelled else { return }
            phase = .done(outcome)
        }
    }

    /// Closes the view; a test still running is stopped.
    func close() {
        work?.cancel()
        work = nil
        shown = false
        phase = .reading
    }

    /// For renders: show a given state without reading or testing.
    func show(_ phase: Phase, setup: NetworkCheck.Setup) {
        work?.cancel()
        self.setup = setup
        self.phase = phase
        shown = true
    }
}

struct NetworkView: View {
    @ObservedObject var tester: NetworkTester

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Test my network").font(.body.weight(.semibold))
                Spacer()
                Button { tester.close() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).accessibilityLabel("Close")
            }
            switch tester.phase {
            case .reading:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking at your connection…").foregroundStyle(Ink.muted) }
                    .font(.callout)
            case .ready:
                Text(NetworkCheck.explainer).font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                Button("Start test") { tester.start() }.buttonStyle(RecommendedButton()).font(.callout)
                facts(nil)
            case .testing(let started):
                TimelineView(.periodic(from: started, by: 1)) { t in
                    let left = max(0, NetworkCheck.testSeconds - Int(t.date.timeIntervalSince(started)))
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(left > 0 ? "Testing, up to \(left) seconds more…" : "Finishing…").foregroundStyle(Ink.text)
                    }
                    .font(.callout)
                }
                Text("Your connection is busy while it runs, so calls and downloads may slow for a moment.")
                    .font(.callout).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                Button("Stop test") { tester.close(); tester.open() }.buttonStyle(.bordered).controlSize(.small)
            case .done(let outcome):
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: symbol(outcome)).foregroundStyle(tint(outcome))
                    Text(NetworkCheck.verdict(outcome)).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                }
                if case .done(let r) = outcome { facts(r) } else { facts(nil) }
                Button("Test again") { tester.start() }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.edge, lineWidth: 1))
    }

    /// The facts, one plain line each, as "The facts" reads on a card.
    @ViewBuilder func facts(_ r: NetworkCheck.Result?) -> some View {
        if let s = tester.setup {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(NetworkCheck.lines(r, s), id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("·").foregroundStyle(Ink.muted)
                        Text(line).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
        }
    }

    func symbol(_ o: NetworkCheck.Outcome) -> String {
        guard case .done(let r) = o else { return "exclamationmark.triangle.fill" }
        return r.rpm <= NetworkCheck.poorRPM ? "exclamationmark.triangle.fill" : r.rpm < NetworkCheck.goodRPM ? "minus.circle.fill" : "checkmark.circle.fill"
    }

    func tint(_ o: NetworkCheck.Outcome) -> Color {
        guard case .done(let r) = o else { return .orange }
        return r.rpm <= NetworkCheck.poorRPM ? .orange : r.rpm < NetworkCheck.goodRPM ? .yellow : .green
    }
}
