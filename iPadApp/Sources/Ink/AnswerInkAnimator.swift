import Foundation
import PencilKit
import SwiftUI

/// Pure, dependency-free pacing math for the per-stroke reveal.
///
/// The reveal advances a stroke by a number of path points each frame. With a
/// FIXED points-per-frame, a very long answer (up to the 120-word maximum) can
/// take on the order of a minute to fully draw — too slow. This type computes an
/// EFFECTIVE points-per-frame that keeps the total animation within a documented
/// bounded target while preserving the natural, unhurried pacing of short
/// answers.
///
/// Policy:
/// - Short answers keep the base cadence exactly (never sped up): they are
///   already well under the target duration, so their feel is preserved.
/// - Long answers are sped up JUST enough (points-per-frame is scaled up) so the
///   whole reveal finishes within `targetMaxDuration`.
/// - The stroke ORDER and per-stroke shape are never changed — only how many
///   points are revealed per frame — so natural drawing order is preserved.
///
/// Bounded target: at 60fps (`frameInterval` = 1/60s) the default
/// `targetMaxDuration` of 15s caps a maximum ~120-word answer at <= 15 seconds
/// instead of ~1 minute.
public struct AnswerPacing: Sendable, Equatable {
    /// Baseline points revealed per frame for short answers.
    public var basePointsPerFrame: Double
    /// Upper bound on total reveal time for the whole answer.
    public var targetMaxDuration: Duration
    /// Never reveal more than this many points per frame, so even the largest
    /// workload keeps SOME visible stroke motion rather than snapping.
    public var maxPointsPerFrame: Double

    public init(
        basePointsPerFrame: Double = 2.2,
        targetMaxDuration: Duration = .seconds(15),
        maxPointsPerFrame: Double = 64
    ) {
        self.basePointsPerFrame = basePointsPerFrame
        self.targetMaxDuration = targetMaxDuration
        self.maxPointsPerFrame = maxPointsPerFrame
    }

    /// Total frames a workload of `totalRevealSteps` reveal-steps takes at a
    /// given points-per-frame. `totalRevealSteps` is the sum over strokes of
    /// `max(pathPointCount - 1, 1)` (the per-stroke work the reveal performs).
    public static func frameCount(totalRevealSteps: Int, pointsPerFrame: Double) -> Int {
        guard totalRevealSteps > 0, pointsPerFrame > 0 else { return 0 }
        // Each stroke needs at least one frame; the reveal loop advances by
        // `pointsPerFrame` until it covers the stroke's steps.
        return Int((Double(totalRevealSteps) / pointsPerFrame).rounded(.up))
    }

    /// Seconds represented by a `Duration`.
    private static func seconds(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    /// The EFFECTIVE points-per-frame for a workload, so the total reveal fits
    /// within `targetMaxDuration` at the given `frameInterval`. Short workloads
    /// return `basePointsPerFrame` unchanged; large workloads scale up (clamped
    /// to `maxPointsPerFrame`). Pure and deterministic.
    ///
    /// - Parameter totalRevealSteps: sum over strokes of `max(pathPoints-1, 1)`.
    public func effectivePointsPerFrame(totalRevealSteps: Int, frameInterval: Duration) -> Double {
        guard totalRevealSteps > 0 else { return basePointsPerFrame }
        let frameSeconds = AnswerPacing.seconds(frameInterval)
        guard frameSeconds > 0 else { return basePointsPerFrame }
        let targetSeconds = AnswerPacing.seconds(targetMaxDuration)
        guard targetSeconds > 0 else { return maxPointsPerFrame }

        // Duration at the base cadence.
        let baseFrames = AnswerPacing.frameCount(totalRevealSteps: totalRevealSteps, pointsPerFrame: basePointsPerFrame)
        let baseDuration = Double(baseFrames) * frameSeconds
        if baseDuration <= targetSeconds {
            // Short/medium answers: preserve the natural base cadence exactly.
            return basePointsPerFrame
        }
        // Long answers: choose the smallest points-per-frame that fits the
        // target. We must satisfy `frameCount(steps, ppf) <= framesAllowed`,
        // where `frameCount` rounds UP. Using the floored frame budget as the
        // denominator guarantees the rounded-up frame count still fits within
        // the target duration (no marginal overshoot from rounding).
        let framesAllowed = (targetSeconds / frameSeconds).rounded(.down)
        guard framesAllowed >= 1 else { return maxPointsPerFrame }
        let needed = Double(totalRevealSteps) / framesAllowed
        return min(max(needed, basePointsPerFrame), maxPointsPerFrame)
    }

    /// Total reveal-steps for a composed answer at a given render width: sum over
    /// every stroke of `max(pathPointCount - 1, 1)`. Uses the same PKStroke path
    /// the reveal animates, so pacing matches the actual workload.
    @MainActor
    public static func totalRevealSteps(for answer: ComposedAnswer, width: CGFloat = 3.0) -> Int {
        let strokes = InkStrokeBuilder.strokes(from: answer, width: width)
        return strokes.reduce(0) { $0 + max($1.path.count - 1, 1) }
    }
}

/// Drives the progressive reveal of answer ink in real stroke order.
///
/// The engine owns a `PKDrawing` that grows over time: it appends fully-revealed
/// strokes and, for the stroke currently being drawn, appends a `substroke`
/// prefix that lengthens each frame. It is cancellable via a monotonic revision
/// so clearing/new operations or a style change abandon an in-flight reveal.
///
/// Reduce Motion is honored per the accessibility contract: instead of a
/// per-stroke reveal, the whole answer (or line-by-line) appears without
/// stroke-level motion.
@MainActor
@Observable
public final class AnswerInkAnimator {
    /// The drawing currently visible. The view renders exactly this.
    public private(set) var drawing = PKDrawing()
    /// True while a reveal is running.
    public private(set) var isAnimating = false
    /// Set true once the full answer is on screen (frame completion signal).
    public private(set) var isComplete = false

    /// Frame cadence for per-stroke reveal. ~60 fps.
    private let frameInterval: Duration
    /// Baseline points revealed per frame along a stroke (short-answer cadence).
    private let pointsPerFrame: Double
    /// Pacing policy that dynamically scales `pointsPerFrame` up for long answers
    /// so the whole reveal stays within a bounded target duration.
    private let pacing: AnswerPacing
    private var revision: UInt64 = 0
    private var task: Task<Void, Never>?
    /// Strokes of earlier answers on this page; every reveal draws on top.
    private var committed: [PKStroke] = []

    /// Keeps everything currently shown as permanent page ink, so the next
    /// reveal adds a new answer instead of replacing this one.
    public func commitCurrent() {
        committed = drawing.strokes
    }

    public init(
        frameInterval: Duration = .milliseconds(16),
        pointsPerFrame: Double = 2.2,
        pacing: AnswerPacing? = nil
    ) {
        self.frameInterval = frameInterval
        self.pointsPerFrame = pointsPerFrame
        // Default pacing shares the base cadence so short answers are unchanged.
        self.pacing = pacing ?? AnswerPacing(basePointsPerFrame: pointsPerFrame)
    }

    /// Cancels any in-flight reveal and clears the visible drawing.
    public func reset() {
        revision &+= 1
        task?.cancel()
        task = nil
        isAnimating = false
        isComplete = false
        committed = []
        drawing = PKDrawing()
    }

    /// Immediately shows the full answer with no animation (used for Reduce
    /// Motion "immediate" mode and for recompose-after-style-change when a
    /// reveal already completed).
    public func showComplete(_ answer: ComposedAnswer, width: CGFloat = 3.0) {
        revision &+= 1
        task?.cancel()
        task = nil
        drawing = PKDrawing(strokes: committed + InkStrokeBuilder.strokes(from: answer, width: width))
        isAnimating = false
        isComplete = true
    }

    /// Begins revealing `answer`. When `reduceMotion` is true, reveals by whole
    /// line (or immediately if `immediateWhenReduced`); otherwise per stroke.
    ///
    /// Returns the revision identifying this reveal so a caller can await exactly
    /// this reveal's completion (see `awaitCompletion(of:)`) without being fooled
    /// by a later reveal.
    @discardableResult
    public func reveal(
        _ answer: ComposedAnswer,
        reduceMotion: Bool,
        immediateWhenReduced: Bool = false,
        width: CGFloat = 3.0
    ) -> UInt64 {
        revision &+= 1
        let myRevision = revision
        task?.cancel()
        drawing = PKDrawing(strokes: committed)
        isComplete = false

        if reduceMotion && immediateWhenReduced {
            showComplete(answer, width: width)
            return myRevision
        }

        isAnimating = true
        task = Task { [weak self] in
            guard let self else { return }
            if reduceMotion {
                await self.revealByLine(answer, width: width, revision: myRevision)
            } else {
                await self.revealByStroke(answer, width: width, revision: myRevision)
            }
        }
        return myRevision
    }

    /// Awaits completion of the reveal identified by `revision`. Returns true if
    /// that specific reveal completed, or false if it was superseded/cancelled by
    /// a newer reveal or a reset before finishing. Polls cooperatively so it is
    /// cancellation- and revision-safe: a stale reveal never reports completion.
    public func awaitCompletion(of targetRevision: UInt64) async -> Bool {
        while !Task.isCancelled {
            // A newer reveal (or reset) superseded this one: it will never
            // complete, so report non-completion rather than hanging.
            if revision != targetRevision { return false }
            if isComplete { return true }
            try? await Task.sleep(for: .milliseconds(8))
        }
        return false
    }

    // MARK: - Reveal strategies

    private func revealByLine(_ answer: ComposedAnswer, width: CGFloat, revision myRevision: UInt64) async {
        var shown: [PKStroke] = committed
        let maxLine = answer.glyphs.map(\.line).max() ?? 0
        for line in 0...max(maxLine, 0) {
            guard isCurrent(myRevision), !Task.isCancelled else { return }
            for glyph in answer.glyphs where glyph.line == line {
                for st in glyph.strokes {
                    if let s = InkStrokeBuilder.stroke(from: st, width: width) { shown.append(s) }
                }
            }
            drawing = PKDrawing(strokes: shown)
            // A gentle per-line beat; still not stroke-level motion.
            try? await Task.sleep(for: .milliseconds(120))
        }
        finish(myRevision)
    }

    private func revealByStroke(_ answer: ComposedAnswer, width: CGFloat, revision myRevision: UInt64) async {
        let allStrokes = InkStrokeBuilder.strokes(from: answer, width: width)
        var completed: [PKStroke] = committed
        completed.reserveCapacity(committed.count + allStrokes.count)

        // Pace against the complete ordered workload. A single frame may finish
        // several very short strokes; without that batching, one sleep per stroke
        // creates an unavoidable duration floor that can exceed the 15-second
        // target even when pointsPerFrame is increased. Order is still strict:
        // budget is consumed from the current stroke before advancing to the next.
        let stepCounts = allStrokes.map { max($0.path.count - 1, 1) }
        let totalSteps = stepCounts.reduce(0, +)
        let effectivePointsPerFrame = pacing.effectivePointsPerFrame(
            totalRevealSteps: totalSteps, frameInterval: frameInterval
        )

        var strokeIndex = 0
        var revealedInCurrentStroke = 0.0

        while strokeIndex < allStrokes.count {
            guard isCurrent(myRevision), !Task.isCancelled else { return }
            var frameBudget = effectivePointsPerFrame
            var partial: PKStroke?

            // Consume this frame's budget in strict stroke order. This can commit
            // multiple tiny strokes in one display frame for a long answer, then
            // use `substroke` for the first stroke the budget only partly covers.
            while frameBudget > 0, strokeIndex < allStrokes.count {
                let stroke = allStrokes[strokeIndex]
                let strokeSteps = Double(stepCounts[strokeIndex])
                let remaining = strokeSteps - revealedInCurrentStroke

                if frameBudget >= remaining {
                    completed.append(stroke)
                    frameBudget -= remaining
                    strokeIndex += 1
                    revealedInCurrentStroke = 0
                    partial = nil
                } else {
                    revealedInCurrentStroke += frameBudget
                    let fraction = min(revealedInCurrentStroke / strokeSteps, 1)
                    partial = InkStrokeBuilder.partialStroke(stroke, fraction: fraction)
                    frameBudget = 0
                }
            }

            guard isCurrent(myRevision), !Task.isCancelled else { return }
            if let partial {
                drawing = PKDrawing(strokes: completed + [partial])
            } else {
                drawing = PKDrawing(strokes: completed)
            }

            if strokeIndex < allStrokes.count {
                do {
                    try await Task.sleep(for: frameInterval)
                } catch {
                    return
                }
            }
        }
        finish(myRevision)
    }

    private func finish(_ myRevision: UInt64) {
        guard isCurrent(myRevision) else { return }
        isAnimating = false
        isComplete = true
    }

    private func isCurrent(_ candidate: UInt64) -> Bool { candidate == revision }
}
