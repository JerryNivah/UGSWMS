/*
Firestore Schema Summary (from code scan)
=========================================

Collections
-----------
1) users
   - UID fields: uid (doc id), activeRouteId
   - Role/status: role, status, driverStatus
   - Other: email, name, phone, licenseNumber, fcmTokens, lastLat, lastLng
   - Timestamps: createdAt, updatedAt, approvedAt

2) driver_applications
   - UID fields: uid (doc id)
   - Status: status
   - Other: email, name, phone, licenseNo
   - Timestamps: createdAt

3) service_requests
   - UID fields: userUid, assignedDriverUid, assignmentId
   - Type fields: serviceType, wasteType, requestType, source
   - Status fields: status, assignmentStatus
   - Other: quantity, pickupAddressText, pickupArea, notes
   - Bin link fields: binId, binName, lat, lng, openAlertRequestId (on bins)
   - Payment flags: paymentRequired
   - Timestamps: createdAt, updatedAt, assignedAt, completedAt, cancelledAt
   - Admin flags: adminNotifiedNewRequest

4) assignments
   - UID fields: driverUid, userUid, requestId
   - Status fields: status
   - Other: serviceType, pickupAddressText, userEmail, createdBy
   - Timestamps: createdAt, updatedAt, completedAt, cancelledAt
   - Admin flags: adminNotifiedAccepted, userNotifiedAccepted,
     completionNotified, adminNotifiedCompleted

5) routes
   - UID fields: driverUid
   - Status fields: status, animationState
   - Other: stops[], currentStopIndex, polyline, polylinePoints, createdBy
   - Timestamps: createdAt, updatedAt, completedAt, assignedAt (via bins)

6) bins
   - UID fields: assignedDriverUid, assignedRouteId
   - Status fields: status, openAlertStatus
   - Other: name, area, lat, lng, isActive, level, fillLevel
   - Locking: lockedUntil, lastCollectedAt, autoAllocateLockedUntil
   - Timestamps: lastUpdatedAt, updatedAt, assignedAt

7) notifications
   - UID fields: toUid, refId
   - Type fields: type, role, refType, severity
   - Other: title, body, extra, routeId, read, readAt
   - Timestamps: createdAt

8) support_tickets
   - UID fields: senderUid
   - Status fields: status
   - Type fields: priority
   - Other: subject, message, senderRole, senderName, senderEmail, senderPhone
   - Timestamps: createdAt, updatedAt

9) route_events
   - UID fields: driverUid, routeId, binId
   - Type fields: type
   - Other: binTitle, stopIndex
   - Timestamps: createdAt

10) payments
    - UID fields: userUid, serviceRequestId
    - Type fields: currency, provider, status
    - Other: amount, phone, checkoutRequestId, merchantRequestId,
      mpesaReceipt, resultCode, resultDesc
    - Timestamps: createdAt, updatedAt

11) system (docs, not collections in Dart)
    - system/auto_settings: enabled (bool)
    - system/allocator_lock: until, updatedAt

Status / Type Enum Values (seen in code)
----------------------------------------
- users.role: user, driver, driver_pending, pending_driver, admin (implied)
- users.status: pending, active, inactive, deleted
- users.driverStatus: available, busy, offline

- bins.status: normal, warning, critical
- bins.openAlertStatus: pending

- service_requests.status: pending, assigned, accepted, completed, cancelled
- service_requests.assignmentStatus: pending, accepted, completed, cancelled
- service_requests.serviceType: pickup, cleanup, bin_alert
- service_requests.wasteType: general, plastic, organic, glass
- service_requests.requestType: private, public_bin, unknown
- service_requests.source: user_request, bin_alert, unknown

- assignments.status: pending, accepted, completed, cancelled, done (alias)

- routes.status: planned, active, completed, cancelled
- routes.animationState: moving, paused, completed
- routes.stops[].refType: bin

- notifications.type:
  route_assigned, assignment_assigned, driver_assigned, driver_accepted,
  assignment_accepted, assignment_completed, request_completed,
  service_request, driver_approval, support_ticket
- notifications.severity: low, medium, high

- support_tickets.status: open, in_progress, resolved
- support_tickets.priority: low, medium, high

- route_events.type: stop_completed

- payments.status: draft, pending, paid, failed, cancelled
- payments.currency: KES
- payments.provider: mpesa_sandbox
*/
