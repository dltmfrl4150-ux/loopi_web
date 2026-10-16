/**
 * Scheduled purge of accounts whose restore window has ended.
 *
 * This file is not deployed. Deploying it requires the Blaze plan and an
 * explicit operator approval. Until then the job does not run.
 *
 * The function uses the Admin SDK only on the server. No service account
 * file belongs in the Flutter app.
 */
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { getAuth } = require('firebase-admin/auth');
const purge = require('./src/purge');

initializeApp();

exports.purgeExpiredAccounts = onSchedule('every 24 hours', async () => {
  const db = getFirestore();
  const now = Date.now();
  const due = await db.collectionGroup('private')
    .where('status', '==', purge.PENDING)
    .where('purgeAfter', '<=', new Date(now))
    .limit(20)
    .get();

  for (const doc of due.docs) {
    if (doc.id !== 'account') continue;
    const userRef = doc.ref.parent.parent;
    if (!userRef) continue;
    await purgeOneAccount({ db, uid: userRef.id, accountRef: doc.ref, now });
  }

  const resume = await db.collection('deletion_jobs')
    .where('status', 'in', ['running', 'error'])
    .limit(20)
    .get();
  for (const job of resume.docs) {
    const accountRef = db.collection('users').doc(job.id).collection('private').doc('account');
    await purgeOneAccount({ db, uid: job.id, accountRef, now });
  }
});

async function purgeOneAccount({ db, uid, accountRef, now }) {
  const jobRef = db.collection('deletion_jobs').doc(uid);
  const locked = await db.runTransaction(async (tx) => {
    const accountSnap = await tx.get(accountRef);
    const jobSnap = await tx.get(jobRef);
    const jobData = jobSnap.data();
    const resumeJob = jobData && (jobData.status === 'running' || jobData.status === 'error');
    if (!accountSnap.exists) {
      if (!resumeJob) return false;
      return { completed: new Set(jobData.completedSteps || []) };
    }
    const data = accountSnap.data() || {};
    const purgeAfterMs = data.purgeAfter && data.purgeAfter.toMillis
      ? data.purgeAfter.toMillis()
      : null;
    const alreadyLocked = data.status === purge.PURGE_STARTED || !!data.purgeStartedAt;
    const due = purge.isPurgeDue({
      status: data.status,
      purgeStartedAt: data.purgeStartedAt || null,
      purgeAfterMs,
    }, now);
    if (!alreadyLocked && !due) return false;
    if (!alreadyLocked) {
      tx.set(accountRef, {
        status: purge.PURGE_STARTED,
        purgeStartedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    const completed = new Set((jobSnap.data() && jobSnap.data().completedSteps) || []);
    tx.set(jobRef, {
      uid,
      status: 'running',
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { completed };
  });
  if (!locked) return;

  const completed = locked.completed;
  try {
    if (!completed.has('anonymize_routines')) {
      const count = await anonymizeRoutines(db, uid);
      await markStep(jobRef, completed, 'anonymize_routines', count);
    }
    if (!completed.has('scrub_social')) {
      const count = await scrubSocial(db, uid);
      await markStep(jobRef, completed, 'scrub_social', count);
    }
    if (!completed.has('delete_showcase')) {
      const count = await deleteShowcase(db, uid);
      await markStep(jobRef, completed, 'delete_showcase', count);
    }
    if (!completed.has('delete_avatars')) {
      const count = await deletePrefix(`avatars/${uid}`);
      await markStep(jobRef, completed, 'delete_avatars', count);
    }
    if (!completed.has('delete_library')) {
      await db.collection('users').doc(uid).collection('data').doc('library').delete();
      await markStep(jobRef, completed, 'delete_library', 1);
    }
    if (!completed.has('delete_public_profile')) {
      await db.collection('public_profiles').doc(uid).delete();
      await markStep(jobRef, completed, 'delete_public_profile', 1);
    }
    if (!completed.has('delete_user_doc')) {
      await db.collection('users').doc(uid).delete();
      await markStep(jobRef, completed, 'delete_user_doc', 1);
    }
    if (!completed.has('delete_auth')) {
      await deleteAuthUser(uid);
      await markStep(jobRef, completed, 'delete_auth', 1);
    }
    if (!completed.has('delete_private_account')) {
      await accountRef.delete();
      await markStep(jobRef, completed, 'delete_private_account', 1);
    }
    await jobRef.set({
      uid,
      status: 'completed',
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  } catch (error) {
    await jobRef.set({
      uid,
      status: 'error',
      lastErrorCode: error && error.code ? String(error.code) : 'purge-failed',
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    throw error;
  }
}

async function markStep(jobRef, completed, step, deletedCount) {
  completed.add(step);
  await jobRef.set({
    ...purge.jobProgressPatch({ uid: jobRef.id, step, deletedCount }),
    completedSteps: [...completed],
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

async function anonymizeRoutines(db, uid) {
  const fields = purge.anonymizedAuthorFields(uid);
  const snap = await db.collection('community_routines').where('authorId', '==', uid).get();
  let count = 0;
  for (const doc of snap.docs) {
    await doc.ref.set({
      authorId: fields.authorId,
      authorName: fields.authorName,
      authorNickname: fields.authorNickname,
      authorPhotoUrl: FieldValue.delete(),
      'routine.authorId': fields.routineAuthorId,
      'routine.authorName': fields.routineAuthorName,
    }, { merge: true });
    count += 1;
  }
  return count;
}

async function scrubSocial(db, uid) {
  let count = 0;
  count += await removeUidFromArray(db, 'community_routines', 'favoritedBy', uid);
  count += await removeUidFromArray(db, 'community_showcase', 'likedBy', uid);
  return count;
}

async function removeUidFromArray(db, collectionName, field, uid) {
  const snap = await db.collection(collectionName).where(field, 'array-contains', uid).get();
  let count = 0;
  for (const doc of snap.docs) {
    const values = Array.isArray(doc.get(field)) ? doc.get(field).filter((item) => item !== uid) : [];
    const patch = { [field]: values };
    if (field === 'favoritedBy') patch.favoriteCount = values.length;
    if (field === 'likedBy') patch.likesCount = values.length;
    await doc.ref.set(patch, { merge: true });
    const eventRef = doc.ref.collection('favoriteEvents').doc(uid);
    await eventRef.delete();
    count += 1;
  }
  return count;
}

async function collectRoutineUrls(db, authorId, routineUrls) {
  const routineSnap = await db.collection('community_routines').where('authorId', '==', authorId).get();
  for (const doc of routineSnap.docs) {
    const routine = doc.get('routine') || {};
    if (typeof routine.videoUrl === 'string') routineUrls.add(routine.videoUrl);
    if (typeof routine.localFilePath === 'string') routineUrls.add(routine.localFilePath);
  }
}

async function deleteShowcase(db, uid) {
  const routineUrls = new Set();
  await collectRoutineUrls(db, uid, routineUrls);
  await collectRoutineUrls(db, purge.withdrawnAuthorId(uid), routineUrls);
  const snap = await db.collection('community_showcase').where('authorId', '==', uid).get();
  let count = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const objectPath = purge.ownedShowcaseStoragePath({
      ownerUid: uid,
      storagePath: data.storagePath,
      downloadUrl: data.videoUrl || data.recordedPath,
    });
    const downloadUrl = data.videoUrl || data.recordedPath || '';
    const shared = purge.routineReferencesUrl(routineUrls, downloadUrl);
    if (objectPath && !shared) {
      await getStorage().bucket().file(objectPath).delete({ ignoreNotFound: true });
    }
    await doc.ref.delete();
    count += 1;
  }
  return count;
}

async function deletePrefix(prefix) {
  const [files] = await getStorage().bucket().getFiles({ prefix: `${prefix}/` });
  let count = 0;
  for (const file of files) {
    if (!file.name.startsWith(`${prefix}/`) || file.name.includes('..')) continue;
    await file.delete({ ignoreNotFound: true });
    count += 1;
  }
  return count;
}

async function deleteAuthUser(uid) {
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    if (error && error.code === 'auth/user-not-found') return;
    throw error;
  }
}
