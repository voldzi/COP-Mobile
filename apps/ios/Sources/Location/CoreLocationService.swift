@preconcurrency import CoreLocation
import Foundation
import UIKit

enum DeviceLocationError: Error, Equatable {
  case permissionNotDetermined
  case permissionDenied
  case permissionRestricted
  case unavailable
  case timeout
  case invalidSample
}

private struct TransferableDevicePayload: @unchecked Sendable {
  let value: [String: Any]
}

@MainActor
protocol DeviceLocationProviding: AnyObject {
  var permission: String { get }
  var reducedAccuracy: Bool { get }
  var locationAvailable: Bool { get }
  var headingAvailable: Bool { get }

  func requestWhenInUseAuthorization() async -> String
  func currentLocation(timeout: Duration) async throws -> [String: Any]
  func startLocationUpdates(_ receive: @escaping ([String: Any]) -> Void) throws
  func stopLocationUpdates()
  func startHeadingUpdates(_ receive: @escaping ([String: Any]) -> Void) throws
  func stopHeadingUpdates()
  func stopAllUpdates()
}

@MainActor
final class CoreLocationService: NSObject, DeviceLocationProviding, @preconcurrency CLLocationManagerDelegate {
  private let manager: CLLocationManager
  private var authorizationContinuation: CheckedContinuation<String, Never>?
  private var locationContinuation: CheckedContinuation<TransferableDevicePayload, any Error>?
  private var locationTimeoutTask: Task<Void, Never>?
  private var locationReceiver: (([String: Any]) -> Void)?
  private var headingReceiver: (([String: Any]) -> Void)?
  private var orientationObserver: NSObjectProtocol?

  override init() {
    manager = CLLocationManager()
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = kCLDistanceFilterNone
    manager.headingFilter = kCLHeadingFilterNone
    manager.activityType = .other
    manager.pausesLocationUpdatesAutomatically = true
  }

  var permission: String { Self.permission(manager.authorizationStatus) }
  var reducedAccuracy: Bool { manager.accuracyAuthorization == .reducedAccuracy }
  // Every supported iPhone has Core Location; authorization is reported separately.
  // Avoid the synchronous global services query on the main actor (iOS 27 diagnoses it).
  var locationAvailable: Bool { true }
  var headingAvailable: Bool { CLLocationManager.headingAvailable() }

  func requestWhenInUseAuthorization() async -> String {
    guard manager.authorizationStatus == .notDetermined else { return permission }
    return await withCheckedContinuation { continuation in
      authorizationContinuation = continuation
      manager.requestWhenInUseAuthorization()
    }
  }

  func currentLocation(timeout: Duration = .seconds(15)) async throws -> [String: Any] {
    try validateAuthorization()
    guard locationAvailable else { throw DeviceLocationError.unavailable }
    guard locationContinuation == nil else { throw DeviceLocationError.unavailable }

    let payload = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        locationContinuation = continuation
        manager.requestLocation()
        locationTimeoutTask = Task { [weak self] in
          try? await Task.sleep(for: timeout)
          guard !Task.isCancelled else { return }
          self?.finishCurrentLocation(.failure(DeviceLocationError.timeout))
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.finishCurrentLocation(.failure(CancellationError()))
      }
    }
    return payload.value
  }

  func startLocationUpdates(_ receive: @escaping ([String: Any]) -> Void) throws {
    try validateAuthorization()
    guard locationAvailable else { throw DeviceLocationError.unavailable }
    locationReceiver = receive
    manager.startUpdatingLocation()
  }

  func stopLocationUpdates() {
    locationReceiver = nil
    manager.stopUpdatingLocation()
  }

  func startHeadingUpdates(_ receive: @escaping ([String: Any]) -> Void) throws {
    try validateAuthorization()
    guard headingAvailable else { throw DeviceLocationError.unavailable }
    headingReceiver = receive
    if orientationObserver == nil {
      UIDevice.current.beginGeneratingDeviceOrientationNotifications()
      updateHeadingOrientation()
      orientationObserver = NotificationCenter.default.addObserver(
        forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.updateHeadingOrientation() }
      }
    }
    manager.startUpdatingHeading()
  }

  func stopHeadingUpdates() {
    headingReceiver = nil
    manager.stopUpdatingHeading()
    if let orientationObserver {
      NotificationCenter.default.removeObserver(orientationObserver)
      self.orientationObserver = nil
    }
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
  }

  func stopAllUpdates() {
    stopLocationUpdates()
    stopHeadingUpdates()
    finishCurrentLocation(.failure(CancellationError()))
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorizationContinuation?.resume(returning: permission)
    authorizationContinuation = nil
    if permission != "granted" {
      stopAllUpdates()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last, let sample = Self.locationSample(location, reducedAccuracy: reducedAccuracy)
    else {
      finishCurrentLocation(.failure(DeviceLocationError.invalidSample))
      return
    }
    if locationContinuation != nil {
      finishCurrentLocation(.success(TransferableDevicePayload(value: sample)))
    }
    locationReceiver?(sample)
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    guard let sample = Self.headingSample(newHeading) else { return }
    headingReceiver?(sample)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    finishCurrentLocation(.failure(error))
  }

  private func validateAuthorization() throws {
    switch manager.authorizationStatus {
    case .notDetermined: throw DeviceLocationError.permissionNotDetermined
    case .denied: throw DeviceLocationError.permissionDenied
    case .restricted: throw DeviceLocationError.permissionRestricted
    case .authorizedAlways, .authorizedWhenInUse: return
    @unknown default: throw DeviceLocationError.unavailable
    }
  }

  private func updateHeadingOrientation() {
    switch UIDevice.current.orientation {
    case .portrait: manager.headingOrientation = .portrait
    case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
    case .landscapeLeft: manager.headingOrientation = .landscapeLeft
    case .landscapeRight: manager.headingOrientation = .landscapeRight
    default: break
    }
  }

  private func finishCurrentLocation(
    _ result: Result<TransferableDevicePayload, any Error>
  ) {
    guard let continuation = locationContinuation else { return }
    locationContinuation = nil
    locationTimeoutTask?.cancel()
    locationTimeoutTask = nil
    continuation.resume(with: result)
  }

  static func permission(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: "notDetermined"
    case .restricted: "restricted"
    case .denied: "denied"
    case .authorizedAlways, .authorizedWhenInUse: "granted"
    @unknown default: "unavailable"
    }
  }

  static func locationSample(_ location: CLLocation, reducedAccuracy: Bool, now: Date = Date())
    -> [String: Any]?
  {
    let coordinate = location.coordinate
    guard CLLocationCoordinate2DIsValid(coordinate), location.horizontalAccuracy >= 0,
      location.timestamp.timeIntervalSince(now) <= 10
    else { return nil }
    let live = abs(location.timestamp.timeIntervalSince(now)) <= 5
    return [
      "sampleId": UUID().uuidString.lowercased(),
      "measuredAt": timestamp(location.timestamp),
      "receivedAt": timestamp(now),
      "source": live ? "live" : "cached",
      "latitude": coordinate.latitude,
      "longitude": coordinate.longitude,
      "horizontalAccuracyM": location.horizontalAccuracy,
      "altitudeM": location.verticalAccuracy >= 0 ? location.altitude : NSNull(),
      "verticalAccuracyM": location.verticalAccuracy >= 0 ? location.verticalAccuracy : NSNull(),
      "speedMps": location.speed >= 0 ? location.speed : NSNull(),
      "courseDeg": location.course >= 0 && location.course < 360 ? location.course : NSNull(),
      "reducedAccuracy": reducedAccuracy,
      "valid": true,
    ]
  }

  static func headingSample(_ heading: CLHeading, now: Date = Date()) -> [String: Any]? {
    guard heading.magneticHeading >= 0, heading.magneticHeading < 360 else { return nil }
    let calibrated = heading.headingAccuracy >= 0
    let trueHeading: Any =
      heading.trueHeading >= 0 && heading.trueHeading < 360 ? heading.trueHeading : NSNull()
    return [
      "sampleId": UUID().uuidString.lowercased(),
      "measuredAt": timestamp(heading.timestamp),
      "receivedAt": timestamp(now),
      "source": abs(heading.timestamp.timeIntervalSince(now)) <= 5 ? "live" : "cached",
      "magneticHeadingDeg": heading.magneticHeading,
      "trueHeadingDeg": trueHeading,
      "accuracyDeg": calibrated ? heading.headingAccuracy : 0,
      "reference": trueHeading is NSNull ? "magneticNorth" : "trueNorth",
      "calibration": calibrated ? "calibrated" : "uncalibrated",
      "valid": calibrated,
    ]
  }

  private static func timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}
