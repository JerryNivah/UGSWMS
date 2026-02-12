"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onRouteWrite = exports.onDriverWrite = exports.onBinWrite = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const firebase_functions_1 = require("firebase-functions");
admin.initializeApp();
const db = admin.firestore();
const MAX_STOPS_PER_ROUTE = 6;
const CLUSTER_RADIUS_KM = 2.5;
const LOCK_PATH = "system/allocator_lock";
const AUTO_ENABLED_PATH = "system/auto_settings";
// -------------------- helpers --------------------
function haversineKm(aLat, aLng, bLat, bLng) {
    const R = 6371;
    const dLat = (bLat - aLat) * Math.PI / 180;
    const dLng = (bLng - aLng) * Math.PI / 180;
    const s1 = Math.sin(dLat / 2), s2 = Math.sin(dLng / 2);
    const q = s1 * s1 + Math.cos(aLat * Math.PI / 180) * Math.cos(bLat * Math.PI / 180) * s2 * s2;
    return 2 * R * Math.asin(Math.min(1, Math.sqrt(q)));
}
async function isAutoEnabled() {
    var _a;
    const snap = await db.doc(AUTO_ENABLED_PATH).get();
    if (!snap.exists)
        return true; // default ON
    return ((_a = snap.data()) === null || _a === void 0 ? void 0 : _a.enabled) !== false;
}
async function acquireLock() {
    const lockRef = db.doc(LOCK_PATH);
    try {
        await db.runTransaction(async (tx) => {
            var _a;
            const snap = await tx.get(lockRef);
            const now = admin.firestore.Timestamp.now();
            const leaseMs = 20000;
            if (snap.exists) {
                const until = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.until;
                if (until && until.toMillis() > now.toMillis())
                    throw new Error("LOCKED");
            }
            tx.set(lockRef, {
                until: admin.firestore.Timestamp.fromMillis(now.toMillis() + leaseMs),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
        return true;
    }
    catch (e) {
        if (String((e === null || e === void 0 ? void 0 : e.message) || "").includes("LOCKED"))
            return false;
        firebase_functions_1.logger.error("Lock error", e);
        return false;
    }
}
async function releaseLock() {
    await db.doc(LOCK_PATH).set({
        until: admin.firestore.Timestamp.fromMillis(0),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
async function sendDriverAssignmentNotification(driverUid, routeId, stopsCount) {
    const title = "New route assigned";
    const body = `You have been assigned ${stopsCount} bin(s) to collect.`;
    await db.collection("notifications").add({
        toUid: driverUid,
        type: "route_assigned",
        title,
        body,
        routeId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}
// -------------------- core allocator --------------------
async function runAllocator() {
    var _a, _b;
    if (!(await isAutoEnabled()))
        return;
    const gotLock = await acquireLock();
    if (!gotLock)
        return;
    try {
        // 1) available drivers
        const driversSnap = await db.collection("users")
            .where("role", "==", "driver")
            .where("driverStatus", "==", "available")
            .get();
        if (driversSnap.empty)
            return;
        // 2) critical + unassigned bins
        const binsSnap = await db.collection("bins")
            .where("status", "==", "critical")
            .where("assignedDriverUid", "==", null)
            .get();
        if (binsSnap.empty)
            return;
        const drivers = driversSnap.docs.map(d => ({ uid: d.id, ...d.data() }));
        const bins = binsSnap.docs.map(b => ({ id: b.id, ...b.data() }));
        // greedy clustering per driver
        for (const drv of drivers) {
            if (!bins.length)
                break;
            const dLat = (_a = drv.lastLat) !== null && _a !== void 0 ? _a : null;
            const dLng = (_b = drv.lastLng) !== null && _b !== void 0 ? _b : null;
            if (dLat == null || dLng == null)
                continue;
            // nearest bin to this driver
            bins.sort((x, y) => haversineKm(dLat, dLng, x.lat, x.lng) - haversineKm(dLat, dLng, y.lat, y.lng));
            const first = bins.shift();
            if (!first)
                continue;
            const cluster = [first];
            const remaining = [];
            // add nearby bins around that first bin
            for (const b of bins) {
                const dist = haversineKm(first.lat, first.lng, b.lat, b.lng);
                if (dist <= CLUSTER_RADIUS_KM && cluster.length < MAX_STOPS_PER_ROUTE) {
                    cluster.push(b);
                }
                else {
                    remaining.push(b);
                }
            }
            bins.length = 0;
            bins.push(...remaining);
            const routeRef = db.collection("routes").doc();
            const routeId = routeRef.id;
            // Transaction to avoid race conditions
            await db.runTransaction(async (tx) => {
                var _a;
                const drvRef = db.collection("users").doc(drv.uid);
                const drvNow = await tx.get(drvRef);
                if (!drvNow.exists)
                    return;
                if (((_a = drvNow.data()) === null || _a === void 0 ? void 0 : _a.driverStatus) !== "available")
                    return;
                const stops = cluster.map((b) => {
                    var _a;
                    return ({
                        refType: "bin",
                        refId: b.id,
                        title: (_a = b.name) !== null && _a !== void 0 ? _a : "Bin",
                        lat: b.lat,
                        lng: b.lng,
                        etaMin: null,
                        done: false,
                    });
                });
                tx.set(routeRef, {
                    driverUid: drv.uid,
                    status: "active",
                    stops,
                    polyline: null,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    createdBy: "system",
                });
                tx.update(drvRef, {
                    driverStatus: "busy",
                    activeRouteId: routeId,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                for (const b of cluster) {
                    tx.update(db.collection("bins").doc(b.id), {
                        assignedDriverUid: drv.uid,
                        assignedRouteId: routeId,
                        assignedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }
            });
            await sendDriverAssignmentNotification(drv.uid, routeId, cluster.length);
        }
    }
    finally {
        await releaseLock();
    }
}
// -------------------- triggers --------------------
// Trigger 1: bin becomes critical OR critical stays unassigned
exports.onBinWrite = (0, firestore_1.onDocumentWritten)("bins/{binId}", async (event) => {
    var _a, _b, _c, _d;
    const after = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.after) === null || _b === void 0 ? void 0 : _b.data();
    const before = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.before) === null || _d === void 0 ? void 0 : _d.data();
    if (!after)
        return;
    const becameCritical = (before === null || before === void 0 ? void 0 : before.status) !== "critical" && after.status === "critical";
    const criticalUnassigned = after.status === "critical" && after.assignedDriverUid == null;
    if (becameCritical || criticalUnassigned) {
        await runAllocator();
    }
});
// Trigger 2: driver becomes available
exports.onDriverWrite = (0, firestore_1.onDocumentWritten)("users/{uid}", async (event) => {
    var _a, _b, _c, _d;
    const after = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.after) === null || _b === void 0 ? void 0 : _b.data();
    const before = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.before) === null || _d === void 0 ? void 0 : _d.data();
    if (!after)
        return;
    if (after.role !== "driver")
        return;
    const becameAvailable = (before === null || before === void 0 ? void 0 : before.driverStatus) !== "available" && after.driverStatus === "available";
    if (becameAvailable) {
        await runAllocator();
    }
});
// Trigger 3: route completion -> free driver + optionally clear bins
exports.onRouteWrite = (0, firestore_1.onDocumentWritten)("routes/{routeId}", async (event) => {
    var _a, _b, _c, _d;
    const after = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.after) === null || _b === void 0 ? void 0 : _b.data();
    const before = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.before) === null || _d === void 0 ? void 0 : _d.data();
    if (!after)
        return;
    const driverUid = after.driverUid;
    if (!driverUid)
        return;
    const justCompleted = (before === null || before === void 0 ? void 0 : before.status) !== "completed" && after.status === "completed";
    const justCancelled = (before === null || before === void 0 ? void 0 : before.status) !== "cancelled" && after.status === "cancelled";
    if (!(justCompleted || justCancelled))
        return;
    await db.collection("users").doc(driverUid).set({
        driverStatus: "available",
        activeRouteId: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    // Optional: when completed, mark bins "normal"/"empty" and unassign
    // (depends on your simulation rules)
});
