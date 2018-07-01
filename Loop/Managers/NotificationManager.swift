//
//  NotificationManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import UserNotifications
import LoopKit


struct NotificationManager {
    enum Category: String {
        case bolusFailure
        case loopNotRunning
        case pumpBatteryLow
        case pumpReservoirEmpty
        case pumpReservoirLow
        case remoteTemp
    }

    enum Action: String {
        case retryBolus
    }

    enum UserInfoKey: String {
        case bolusAmount
        case bolusStartDate
    }

    private static var notificationCategories: Set<UNNotificationCategory> {
        var categories = [UNNotificationCategory]()

        let retryBolusAction = UNNotificationAction(
            identifier: Action.retryBolus.rawValue,
            title: NSLocalizedString("Retry", comment: "The title of the notification action to retry a bolus command"),
            options: []
        )

        categories.append(UNNotificationCategory(
            identifier: Category.bolusFailure.rawValue,
            actions: [retryBolusAction],
            intentIdentifiers: [],
            options: []
        ))

        return Set(categories)
    }

    static func authorize(delegate: UNUserNotificationCenterDelegate) {
        let center = UNUserNotificationCenter.current()

        center.delegate = delegate
        center.requestAuthorization(options: [.badge, .sound, .alert], completionHandler: { _, _ in })
        center.setNotificationCategories(notificationCategories)
    }

    // MARK: - Notifications

    static func sendBolusFailureNotification(for error: Error, units: Double, at startDate: Date) {
        let notification = UNMutableNotificationContent()

        notification.title = NSLocalizedString("Bolus", comment: "The notification title for a bolus failure")

        switch error {
        case let error as SetBolusError:
            notification.subtitle = error.errorDescriptionWithUnits(units)
            notification.body = String(format: "%@ %@", error.failureReason!, error.recoverySuggestion!)
        case let error as LocalizedError:
            notification.body = error.errorDescription ?? error.localizedDescription
        default:
            notification.body = error.localizedDescription
        }

        notification.sound = UNNotificationSound.default()

        if startDate.timeIntervalSinceNow >= TimeInterval(minutes: -5) {
            notification.categoryIdentifier = Category.bolusFailure.rawValue
        }

        notification.userInfo = [
            UserInfoKey.bolusAmount.rawValue: units,
            UserInfoKey.bolusStartDate.rawValue: startDate
        ]

        let request = UNNotificationRequest(
            // Only support 1 bolus notification at once
            identifier: Category.bolusFailure.rawValue,
            content: notification,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // Cancel any previous scheduled notifications in the Loop Not Running category
    static func clearPendingNotificationRequests() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    static func scheduleLoopNotRunningNotifications() {
        // Give a little extra time for a loop-in-progress to complete
        let gracePeriod = TimeInterval(minutes: 0.5)

        for minutes: Double in [20, 40, 60, 120] {
            let notification = UNMutableNotificationContent()
            let failureInterval = TimeInterval(minutes: minutes)

            let formatter = DateComponentsFormatter()
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .full

            if let failueIntervalString = formatter.string(from: failureInterval)?.localizedLowercase {
                notification.body = String(format: NSLocalizedString("Loop has not completed successfully in %@", comment: "The notification alert describing a long-lasting loop failure. The substitution parameter is the time interval since the last loop"), failueIntervalString)
            }

            notification.title = NSLocalizedString("Loop Failure", comment: "The notification title for a loop failure")
            notification.sound = UNNotificationSound.default()
            notification.categoryIdentifier = Category.loopNotRunning.rawValue
            notification.threadIdentifier = Category.loopNotRunning.rawValue

            let request = UNNotificationRequest(
                identifier: "\(Category.loopNotRunning.rawValue)\(failureInterval)",
                content: notification,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: failureInterval + gracePeriod,
                    repeats: false
                )
            )

            UNUserNotificationCenter.current().add(request)
        }
    }

    static func sendPumpBatteryLowNotification() {
        let notification = UNMutableNotificationContent()

        notification.title = NSLocalizedString("Pump Battery Low", comment: "The notification title for a low pump battery")
        notification.body = NSLocalizedString("Change the pump battery immediately", comment: "The notification alert describing a low pump battery")
        notification.sound = UNNotificationSound.default()
        notification.categoryIdentifier = Category.pumpBatteryLow.rawValue

        let request = UNNotificationRequest(
            identifier: Category.pumpBatteryLow.rawValue,
            content: notification,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    static func sendPumpReservoirEmptyNotification() {
        let notification = UNMutableNotificationContent()

        notification.title = NSLocalizedString("Pump Reservoir Empty", comment: "The notification title for an empty pump reservoir")
        notification.body = NSLocalizedString("Change the pump reservoir now", comment: "The notification alert describing an empty pump reservoir")
        notification.sound = UNNotificationSound.default()
        notification.categoryIdentifier = Category.pumpReservoirEmpty.rawValue

        let request = UNNotificationRequest(
            // Not a typo: this should replace any pump reservoir low notifications
            identifier: Category.pumpReservoirLow.rawValue,
            content: notification,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
    
    static func remoteTempSetNotification(duration: Int, lowTarget: Double, highTarget:Double) {
        let notification = UNMutableNotificationContent()
        if duration < 1 as Int {
            notification.title = NSLocalizedString("Remote Temporary Target Canceled ", comment: "The notification title for a remote temp being canceled")
        }
        else
        {
            let lowTargetString = NumberFormatter.localizedString(from: NSNumber(value: lowTarget), number: .decimal)
            let highTargetString = NumberFormatter.localizedString(from: NSNumber(value: highTarget), number: .decimal)
            
            notification.title = NSLocalizedString("Remote Temporary Target Set ", comment: "The notification title for Remote Target Being Set")
            
            notification.body = String(format: NSLocalizedString(" LowTarget: %1$@ HighTarget: %2$@ Duration: %3$@", comment: "Low Target high Target"), lowTargetString, highTargetString, String(duration))
        }
        notification.sound = UNNotificationSound.default()
        notification.categoryIdentifier = Category.remoteTemp.rawValue
        let request = UNNotificationRequest(
            identifier: Category.remoteTemp.rawValue,
            content: notification,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
        
    }

    static func sendPumpReservoirLowNotificationForAmount(_ units: Double, andTimeRemaining remaining: TimeInterval?) {
        let notification = UNMutableNotificationContent()

        notification.title = NSLocalizedString("Pump Reservoir Low", comment: "The notification title for a low pump reservoir")

        let unitsString = NumberFormatter.localizedString(from: NSNumber(value: units), number: .decimal)

        let intervalFormatter = DateComponentsFormatter()
        intervalFormatter.allowedUnits = [.hour, .minute]
        intervalFormatter.maximumUnitCount = 1
        intervalFormatter.unitsStyle = .full
        intervalFormatter.includesApproximationPhrase = true
        intervalFormatter.includesTimeRemainingPhrase = true

        if let remaining = remaining, let timeString = intervalFormatter.string(from: remaining) {
            notification.body = String(format: NSLocalizedString("%1$@ U left: %2$@", comment: "Low reservoir alert with time remaining format string. (1: Number of units remaining)(2: approximate time remaining)"), unitsString, timeString)
        } else {
            notification.body = String(format: NSLocalizedString("%1$@ U left", comment: "Low reservoir alert format string. (1: Number of units remaining)"), unitsString)
        }

        notification.sound = UNNotificationSound.default()
        notification.categoryIdentifier = Category.pumpReservoirLow.rawValue

        let request = UNNotificationRequest(
            identifier: Category.pumpReservoirLow.rawValue,
            content: notification,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
