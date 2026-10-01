import ActivityKit
import Flutter
import UIKit

/// Owns the local ActivityKit queue; the schedule remains the Dart repository's responsibility.
@MainActor
final class CourseLiveActivityController {
  private let defaults: UserDefaults
  private var syncTask: Task<Void, Never>?
  private static let requestedKey = "course_live_activity_requested_occurrences"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "isAvailable" {
      if #available(iOS 26.0, *) {
        result(true)
      } else {
        result(false)
      }
      return
    }
    guard call.method == "sync" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let enabled = arguments["enabled"] as? Bool,
      let rawCourses = arguments["courses"] as? [[String: Any]]
    else {
      result(FlutterError(code: "invalid_courses", message: "Expected course activity settings", details: nil))
      return
    }
    guard #available(iOS 26.0, *) else {
      result(["scheduledOccurrenceIDs": [], "activitiesEnabled": false])
      return
    }

    // Calls can overlap after a course edit or a settings change. Preserve their order.
    let previous = syncTask
    syncTask = Task { @MainActor [weak self] in
      await previous?.value
      guard let self else { return }
      result(await self.reconcile(enabled: enabled, rawCourses: rawCourses))
    }
  }

  @available(iOS 26.0, *)
  private func reconcile(enabled: Bool, rawCourses: [[String: Any]]) async -> [String: Any] {
    let now = Date()
    var requested = (defaults.dictionary(forKey: Self.requestedKey) as? [String: Double] ?? [:])
      .filter { $0.value > now.timeIntervalSince1970 }
    var existing = [String: Activity<CourseActivityAttributes>]()
    // Dart plans and limits the queue; it sends no courses when disabled.
    let desired = rawCourses.compactMap(CourseActivityRequest.init)
      .filter { $0.state.expiresAt > now }
    let desiredIDs = Set(desired.map(\.occurrenceID))

    for activity in Activity<CourseActivityAttributes>.activities {
      let id = activity.attributes.occurrenceID
      guard activity.activityState != .dismissed, activity.activityState != .ended else { continue }
      if !desiredIDs.contains(id) || activity.content.state.expiresAt <= now
        || existing[id] != nil {
        await activity.end(nil, dismissalPolicy: .immediate)
        if existing[id] == nil { requested.removeValue(forKey: id) }
      } else {
        existing[id] = activity
      }
    }

    guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
      for activity in existing.values {
        await activity.end(nil, dismissalPolicy: .immediate)
        requested.removeValue(forKey: activity.attributes.occurrenceID)
      }
      // Retain history for activities the user dismissed, but allow cancelled reservations to rearm.
      defaults.set(requested, forKey: Self.requestedKey)
      return ["scheduledOccurrenceIDs": [], "activitiesEnabled": ActivityAuthorizationInfo().areActivitiesEnabled]
    }

    for course in desired {
      let id = course.occurrenceID
      // Trigger the "class started" presentation even if the host is suspended.
      // expiresAt separately controls retention; staleDate does not end the activity.
      let content = ActivityContent(state: course.state, staleDate: course.state.startsAt)
      let alert = AlertConfiguration(
        title: LocalizedStringResource(stringLiteral: course.state.courseName),
        body: LocalizedStringResource(stringLiteral: "即将上课 · \(course.state.location)"),
        sound: .default
      )
      var replacing = false
      if let activity = existing[id] {
        if activity.content.state.visibleFrom != course.state.visibleFrom {
          // A pending activity's scheduled start can't be moved with update().
          await activity.end(nil, dismissalPolicy: .immediate)
          existing.removeValue(forKey: id)
          requested.removeValue(forKey: id)
          replacing = true
        } else {
          if activity.content.state != course.state {
            await activity.update(content)
          }
          continue
        }
      }

      // Do not resurrect a dismissed activity, or create a new reminder after class starts.
      guard (requested[id] == nil || replacing), course.state.startsAt > Date(),
        UIApplication.shared.applicationState == .active
      else { continue }
      do {
        let activity: Activity<CourseActivityAttributes>
        let attributes = CourseActivityAttributes(occurrenceID: id)
        if course.state.visibleFrom > Date() {
          activity = try Activity.request(
            attributes: attributes, content: content, pushType: nil, style: .standard,
            alertConfiguration: alert,
            start: course.state.visibleFrom
          )
        } else {
          activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
          // Alert updates use the system's expanded Island presentation and automatic collapse.
          await activity.update(content, alertConfiguration: alert)
        }
        existing[id] = activity
        requested[id] = course.state.expiresAt.timeIntervalSince1970
      } catch {
        // Other apps share the system limit. Keep successes and retry remaining courses on resume.
        break
      }
    }
    defaults.set(requested, forKey: Self.requestedKey)
    // A partial queue must still acknowledge its successes, otherwise Dart could
    // schedule a second notification for a course already owned by ActivityKit.
    // Ledger-only entries also suppress fallback after the user dismisses an activity.
    let confirmedIDs = desired.compactMap { course in
      existing[course.occurrenceID] != nil || requested[course.occurrenceID] != nil
        ? course.occurrenceID : nil
    }
    return ["scheduledOccurrenceIDs": confirmedIDs, "activitiesEnabled": true]
  }
}

@available(iOS 26.0, *)
struct CourseActivityRequest {
  let occurrenceID: String
  let state: CourseActivityAttributes.ContentState

  init?(_ raw: [String: Any]) {
    guard
      let id = raw["occurrenceID"] as? String,
      let name = raw["courseName"] as? String,
      let location = raw["location"] as? String,
      let startsAt = Self.date(raw["startsAt"]),
      let endsAt = Self.date(raw["endsAt"]),
      let visibleFrom = Self.date(raw["visibleFrom"]),
      let expiresAt = Self.date(raw["expiresAt"])
    else { return nil }
    occurrenceID = id
    state = CourseActivityAttributes.ContentState(
      courseName: name, location: location, campus: raw["campus"] as? String,
      startsAt: startsAt, endsAt: endsAt, visibleFrom: visibleFrom, expiresAt: expiresAt
    )
  }

  private static func date(_ raw: Any?) -> Date? {
    (raw as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
  }
}
