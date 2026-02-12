import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

admin.initializeApp();
const db = admin.firestore();

const MAX_STOPS_PER_ROUTE = 6;
const CLUSTER_RADIUS_KM = 2.5;

const LOCK_PATH = "system/allocator_lock";
const AUTO_ENABLED_PATH = "system/auto_settings";

// -------------------- helpers --------------------
function haversineKm(aLat: number, aLng: number, bLat: number, bLng: number) {
  const R = 6371;
  const dLat = (bLat - aLat) * Math.PI / 180;
  const dLng = (bLng - aLng) * Math.PI / 180;
  const s1 = Math.sin(dLat / 2), s2 = Math.sin(dLng / 2);
  const q = s1 * s1 + Math.cos(aLat * Math.PI / 180) * Math.cos(bLat * Math.PI / 180) * s2 * s2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(q)));
}

async function isAutoEnabled(): Promise<boolean> {
  const snap = await db.doc(AUTO_ENABLED_PATH).get();
  if (!snap.exists) return true; // default ON
  return snap.data()?.enabled !== false;
}

async function acquireLock(): Promise<boolean> {
  const lockRef = db.doc(LOCK_PATH);
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(lockRef);
      const now = admin.firestore.Timestamp.now();
      const leaseMs = 20_000;

      if (snap.exists) {
        const until = snap.data()?.until as admin.firestore.Timestamp | undefined;
        if (until && until.toMillis() > now.toMillis()) throw new Error("LOCKED");
      }

      tx.set(lockRef, {
        until: admin.firestore.Timestamp.fromMillis(now.toMillis() + leaseMs),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });
    return true;
  } catch (e: any) {
    if (String(e?.message || "").includes("LOCKED")) return false;
    logger.error("Lock error", e);
    return false;
  }
}

async function releaseLock() {
  await db.doc(LOCK_PATH).set({
    until: admin.firestore.Timestamp.fromMillis(0),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

async function sendDriverAssignmentNotification(driverUid: string, routeId: string, stopsCount: number) {
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
  if (!(await isAutoEnabled())) return;

  const gotLock = await acquireLock();
  if (!gotLock) return;

  try {
    // 1) available drivers
    const driversSnap = await db.collection("users")
      .where("role", "==", "driver")
      .where("driverStatus", "==", "available")
      .get();

    if (driversSnap.empty) return;

    // 2) critical + unassigned bins
    const binsSnap = await db.collection("bins")
      .where("status", "==", "critical")
      .where("assignedDriverUid", "==", null)
      .get();

    if (binsSnap.empty) return;

    const drivers = driversSnap.docs.map(d => ({ uid: d.id, ...d.data() })) as any[];
    const bins = binsSnap.docs.map(b => ({ id: b.id, ...b.data() })) as any[];

    // greedy clustering per driver
    for (const drv of drivers) {
      if (!bins.length) break;

      const dLat = drv.lastLat ?? null;
      const dLng = drv.lastLng ?? null;
      if (dLat == null || dLng == null) continue;

      // nearest bin to this driver
      bins.sort((x, y) =>
        haversineKm(dLat, dLng, x.lat, x.lng) - haversineKm(dLat, dLng, y.lat, y.lng)
      );
      const first = bins.shift();
      if (!first) continue;

      const cluster: any[] = [first];
      const remaining: any[] = [];

      // add nearby bins around that first bin
      for (const b of bins) {
        const dist = haversineKm(first.lat, first.lng, b.lat, b.lng);
        if (dist <= CLUSTER_RADIUS_KM && cluster.length < MAX_STOPS_PER_ROUTE) {
          cluster.push(b);
        } else {
          remaining.push(b);
        }
      }

      bins.length = 0;
      bins.push(...remaining);

      const routeRef = db.collection("routes").doc();
      const routeId = routeRef.id;

      // Transaction to avoid race conditions
      await db.runTransaction(async (tx) => {
        const drvRef = db.collection("users").doc(drv.uid);
        const drvNow = await tx.get(drvRef);

        if (!drvNow.exists) return;
        if (drvNow.data()?.driverStatus !== "available") return;

        const stops = cluster.map((b) => ({
          refType: "bin",
          refId: b.id,
          title: b.name ?? "Bin",
          lat: b.lat,
          lng: b.lng,
          etaMin: null,
          done: false,
        }));

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
  } finally {
    await releaseLock();
  }
}

// -------------------- triggers --------------------

// Trigger 1: bin becomes critical OR critical stays unassigned
export const onBinWrite = onDocumentWritten("bins/{binId}", async (event) => {
  const after = event.data?.after?.data();
  const before = event.data?.before?.data();
  if (!after) return;

  const becameCritical =
    before?.status !== "critical" && after.status === "critical";

  const criticalUnassigned =
    after.status === "critical" && after.assignedDriverUid == null;

  if (becameCritical || criticalUnassigned) {
    await runAllocator();
  }
});

// Trigger 2: driver becomes available
export const onDriverWrite = onDocumentWritten("users/{uid}", async (event) => {
  const after = event.data?.after?.data();
  const before = event.data?.before?.data();
  if (!after) return;

  if (after.role !== "driver") return;

  const becameAvailable =
    before?.driverStatus !== "available" && after.driverStatus === "available";

  if (becameAvailable) {
    await runAllocator();
  }
});

// Trigger 3: route completion -> free driver + optionally clear bins
export const onRouteWrite = onDocumentWritten("routes/{routeId}", async (event) => {
  const after = event.data?.after?.data();
  const before = event.data?.before?.data();
  if (!after) return;

  const driverUid = after.driverUid as string | undefined;
  if (!driverUid) return;

  const justCompleted = before?.status !== "completed" && after.status === "completed";
  const justCancelled = before?.status !== "cancelled" && after.status === "cancelled";

  if (!(justCompleted || justCancelled)) return;

  await db.collection("users").doc(driverUid).set({
    driverStatus: "available",
    activeRouteId: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // Optional: when completed, mark bins "normal"/"empty" and unassign
  // (depends on your simulation rules)
});
