//
//  EventKitClient.swift
//  https://github.com/persiogv/EventKitClient
//
//  Created by Pérsio on 09/04/19.
//  Copyright © 2019 Persio Vieira. All rights reserved.
//

import EventKit

protocol EventKitClientDelegate: AnyObject {
    func eventKitClient(_ client: EventKitClient, didReceiveStoreChangedNotification notification: Notification)
}

class EventKitClient {
    
    typealias EventsCompletion = (@escaping () throws -> [EKEvent]) -> Void
    typealias RemindersCompletion = (@escaping () throws -> [EKReminder]) -> Void
    typealias ProcessCompletion = (@escaping () throws -> Void) -> Void
    typealias AuthorizationCompletion = EKEventStoreRequestAccessCompletionHandler

    enum EventKitClientError: Error {
        case authorizationPending(entityType: EKEntityType)
        case notAuthorized(entityType: EKEntityType)
        case unhandled(error: Error)
    }
    
    private lazy var store: EKEventStore = EKEventStore()
    private weak var delegate: EventKitClientDelegate?
    
    required init(delegate: EventKitClientDelegate? = nil) {
        self.delegate = delegate
        
        guard delegate == nil else {
            NotificationCenter.default.addObserver(self, selector: #selector(storeChanged(_:)), name: .EKEventStoreChanged, object: nil)
            return
        }
    }
    
    @objc func storeChanged(_ sender: Notification) {
        guard let delegate = delegate else { return }
        delegate.eventKitClient(self, didReceiveStoreChangedNotification: sender)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - First steps
extension EventKitClient {
    
    /// Returns the status for the given entity type
    ///
    /// - Parameter entityType: The entity type
    /// - Returns: The authorization status for the given entity type
    static func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus {
        return EKEventStore.authorizationStatus(for: entityType)
    }
    
    /// Requests authorization for the given entity type
    ///
    /// - Parameters:
    ///   - entityType: The entity type you want access
    ///   - completion: Callback completion handler
    func requestAuthorization(for entityType: EKEntityType, completion: @escaping AuthorizationCompletion) {
        if EKEventStore.authorizationStatus(for: entityType) == .notDetermined {
            return store.requestAccess(to: entityType, completion: completion)
        }
        
        completion(true, nil)
    }
    
    /// Returns the calendars for the given entity type
    ///
    /// - Parameter entityType: The entity type of the calendars you want
    /// - Returns: The user's calendars for the given entity type
    func calendars(for entityType: EKEntityType) -> [EKCalendar] {
        return store.calendars(for: entityType)
    }
}

// MARK: - Handling events
extension EventKitClient {
    
    /// Searchs for events within the date limits
    ///
    /// - Parameters:
    ///   - fromDate: The initial date limit
    ///   - untilDate: The final date limit
    ///   - calendars: The user's calendars for events
    ///   - completion: Callback completion handler
    func searchForEvents(from fromDate: Date,
                         until untilDate: Date,
                         calendars: [EKCalendar]? = nil,
                         completion: @escaping EventsCompletion) {
        let status = EventKitClient.authorizationStatus(for: .event)
        
        switch status {
        case .authorized:
            let predicate = store.predicateForEvents(withStart: fromDate, end: untilDate, calendars: calendars)
            let events = store.events(matching: predicate)
            completion { events }
        case .notDetermined:
            completion {
                throw EventKitClientError.authorizationPending(entityType: .event)
            }
        default:
            completion {
                throw EventKitClientError.notAuthorized(entityType: .event)
            }
        }
    }
    
    /// Saves the given event
    ///
    /// - Parameters:
    ///   - event: The event to be saved
    ///   - recurrently: Flag to indicate if should save future events or not
    ///   - completion: Callback completion handler
    func saveEvent(_ event: EKEvent,
                   recurrently: Bool,
                   completion: @escaping ProcessCompletion) {
        let status = EventKitClient.authorizationStatus(for: .event)
        
        switch status {
        case .authorized:
            do {
                try store.save(event, span: recurrently ? .futureEvents : .thisEvent, commit: true)
                completion {}
            } catch {
                completion {
                    throw EventKitClientError.unhandled(error: error)
                }
            }
        case .notDetermined:
            completion {
                throw EventKitClientError.authorizationPending(entityType: .event)
            }
        default:
            completion {
                throw EventKitClientError.notAuthorized(entityType: .event)
            }
        }
    }
    
    /// Deletes the given event
    ///
    /// - Parameters:
    ///   - event: The event to be deleted
    ///   - recurrently: Flag to indicate if should delete future events or not
    ///   - completion: Callback completion handler
    func deleteEvent(_ event: EKEvent,
                     recurrently: Bool,
                     completion: @escaping ProcessCompletion) {
        let status = EventKitClient.authorizationStatus(for: .event)
        
        switch status {
        case .authorized:
            do {
                try store.remove(event, span: recurrently ? .futureEvents : .thisEvent, commit: true)
                completion {}
            } catch {
                completion {
                    throw EventKitClientError.unhandled(error: error)
                }
            }
        case .notDetermined:
            completion {
                throw EventKitClientError.authorizationPending(entityType: .event)
            }
        default:
            completion {
                throw EventKitClientError.notAuthorized(entityType: .event)
            }
        }
    }
}

// MARK: - Handling reminders
extension EventKitClient {

    /// Searchs for reminders within the date limits
    ///
    /// - Parameters:
    ///   - fromDate: The initial date limit
    ///   - untilDate: The final date limit
    ///   - calendars: The user's calendars for reminders
    ///   - completion: Callback completion handler
    func searchForReminders(from fromDate: Date,
                            until untilDate: Date,
                            calendars: [EKCalendar]? = nil,
                            completion: @escaping RemindersCompletion) {
        
        let status = EventKitClient.authorizationStatus(for: .reminder)
        
        switch status {
        case .authorized:
            let predicate = store.predicateForEvents(withStart: fromDate, end: untilDate, calendars: calendars)
            
            store.fetchReminders(matching: predicate) { (reminders) in
                completion { reminders ?? [] }
            }
        case .notDetermined:
            completion {
                throw EventKitClientError.authorizationPending(entityType: .reminder)
            }
        default:
            completion {
                throw EventKitClientError.notAuthorized(entityType: .reminder)
            }
        }
    }
    
    /// Saves the given reminder
    ///
    /// - Parameters:
    ///   - reminder: The reminder to be saved
    ///   - completion: Callback completion handler
    func saveReminder(_ reminder: EKReminder, completion: @escaping ProcessCompletion) {
        let status = EventKitClient.authorizationStatus(for: .reminder)
        
        switch status {
        case .authorized:
            do {
                try store.save(reminder, commit: true)
                completion {}
            } catch {
                completion {
                    throw EventKitClientError.unhandled(error: error)
                }
            }
        case .notDetermined:
            completion {
                throw EventKitClientError.authorizationPending(entityType: .reminder)
            }
        default:
            completion {
                throw EventKitClientError.notAuthorized(entityType: .reminder)
            }
        }
    }
    
    /// Deletes the given reminder
    ///
    /// - Parameters:
    ///   - reminder: The reminder to be deleted
    ///   - completion: Callback completion handler
    func deleteReminder(_ reminder: EKReminder, completion: @escaping ProcessCompletion) {
        let status = EventKitClient.authorizationStatus(for: .reminder)
        
        switch status {
        case .authorized:
            do {
                try store.remove(reminder, commit: true)
                completion {}
            } catch {
                completion {
                    throw EventKitClientError.unhandled(error: error)
                }
            }
        case .notDetermined:
            completion {
                throw EventKitClientError.authorizationPending(entityType: .reminder)
            }
        default:
            completion {
                throw EventKitClientError.notAuthorized(entityType: .reminder)
            }
        }
    }
}
