/**
 * Local emulator checks for firestore.rules and storage.rules.
 *
 * Uses project id demo-loopi-rules only. The demo- prefix cannot reach
 * production. Do not change the project id to loopi-app-6fdfe.
 *
 * Run:
 *   npm run test:rules
 *
 * The Firestore emulator needs a JDK. This file does not install Java and
 * does not deploy rules.
 */
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';
import 'firebase/compat/storage';

const projectId = 'demo-loopi-rules';
if (!projectId.startsWith('demo-') || projectId.includes('loopi-app')) {
  throw new Error('Refusing to run rules tests against a non-demo project.');
}

const firestoreRules = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8');
const storageRules = readFileSync(new URL('../storage.rules', import.meta.url), 'utf8');
const mediaBytes = new Uint8Array([1, 2, 3, 4]);
const failures = [];

function daysFromNow(days) {
  return firebase.firestore.Timestamp.fromDate(new Date(Date.now() + days * 24 * 60 * 60 * 1000));
}

async function check(name, run, expectDeny) {
  try {
    const promise = run();
    if (expectDeny) {
      await assertFails(promise);
    } else {
      await assertSucceeds(promise);
    }
    console.log(`PASS ${name}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`FAIL ${name}: ${message}`);
    failures.push(name);
  }
}

const testEnv = await initializeTestEnvironment({
  projectId,
  firestore: { rules: firestoreRules, host: '127.0.0.1', port: 8080 },
  storage: { rules: storageRules, host: '127.0.0.1', port: 9199 },
});

try {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const adult = {
      email: 'alice@example.com',
      ageDeclaration: 'at_least_14',
      ageDeclaredAt: firebase.firestore.Timestamp.fromDate(new Date('2026-01-01T00:00:00Z')),
      status: 'active',
    };
    await db.doc('users/alice').set({ nickname: 'Alice', email: 'alice@example.com' });
    await db.doc('users/alice/private/account').set(adult);
    await db.doc('users/alice/data/library').set({ routines: [{ id: 'r1', name: 'Warmup' }] });
    await db.doc('public_profiles/alice').set({
      nickname: 'Alice',
      photoUrl: 'https://example.com/a.jpg',
    });
    await db.doc('users/bob/private/account').set({ ...adult, email: 'bob@example.com' });
    await db.doc('users/cara/private/account').set({
      email: 'cara@example.com',
      ageDeclaration: 'at_least_14',
      ageDeclaredAt: firebase.firestore.Timestamp.fromDate(new Date('2026-01-01T00:00:00Z')),
      status: 'pending_deletion',
      deletionRequestedAt: firebase.firestore.Timestamp.fromDate(new Date('2026-04-01T00:00:00Z')),
      purgeAfter: firebase.firestore.Timestamp.fromDate(new Date('2026-05-01T00:00:00Z')),
    });
    await db.doc('users/dave/private/account').set({
      email: 'dave@example.com',
      ageDeclaration: 'at_least_14',
      status: 'purge_started',
      purgeStartedAt: firebase.firestore.Timestamp.fromDate(new Date('2026-05-02T00:00:00Z')),
    });
    await db.doc('community_routines/post1').set({
      authorId: 'alice',
      authorName: 'Alice',
      authorNickname: 'Alice',
      description: 'section loop',
      routine: { videoId: 'abc123xyz01', videoUrl: 'https://youtu.be/abc123xyz01', name: 'Warmup' },
    });
    await db.doc('community_showcase/show1').set({
      authorId: 'alice',
      authorName: 'Alice',
      videoUrl: 'https://example.com/show.mp4',
    });
    await db.doc('deletion_jobs/alice').set({ uid: 'alice', status: 'running' });
    const storage = context.storage();
    await storage.ref('showcase/alice/take.mp4').put(mediaBytes, { contentType: 'video/mp4' });
    await storage.ref('showcase/cara/take.mp4').put(mediaBytes, { contentType: 'video/mp4' });
  });

  const registered = { firebase: { sign_in_provider: 'google.com', identities: {} } };
  const anonymous = { firebase: { sign_in_provider: 'anonymous', identities: {} } };
  const anon = testEnv.unauthenticatedContext();
  const alice = testEnv.authenticatedContext('alice', registered);
  const bob = testEnv.authenticatedContext('bob', registered);
  const cara = testEnv.authenticatedContext('cara', registered);
  const dave = testEnv.authenticatedContext('dave', registered);
  const guest = testEnv.authenticatedContext('guest', anonymous);
  const erin = testEnv.authenticatedContext('erin', registered);
  const anonDb = anon.firestore();
  const aliceDb = alice.firestore();
  const bobDb = bob.firestore();
  const caraDb = cara.firestore();
  const daveDb = dave.firestore();
  const guestDb = guest.firestore();
  const erinDb = erin.firestore();

  await check('anon cannot read account doc', () => anonDb.doc('users/alice').get(), true);
  await check('anon cannot read private account', () => anonDb.doc('users/alice/private/account').get(), true);
  await check('anon cannot read private library', () => anonDb.doc('users/alice/data/library').get(), true);
  await check('anon can read public profile', () => anonDb.doc('public_profiles/alice').get(), false);
  await check('signed-in user can read public profile', () => bobDb.doc('public_profiles/alice').get(), false);
  await check('owner can read own public profile', () => aliceDb.doc('public_profiles/alice').get(), false);
  await check('anonymous user can read public profile', () => guestDb.doc('public_profiles/alice').get(), false);
  await check('anon can read public routine', () => anonDb.doc('community_routines/post1').get(), false);
  await check('anon can read public showcase doc', () => anonDb.doc('community_showcase/show1').get(), false);
  await check('anon cannot read deletion job', () => anonDb.doc('deletion_jobs/alice').get(), true);

  await check('other user cannot read private account', () => bobDb.doc('users/alice/private/account').get(), true);
  await check('other user cannot read library', () => bobDb.doc('users/alice/data/library').get(), true);
  await check('other user cannot write email onto account', () => bobDb.doc('users/alice').update({ email: 'bob@example.com' }), true);
  await check('other user cannot write private email', () => bobDb.doc('users/alice/private/account').set({ email: 'bob@example.com' }, { merge: true }), true);
  await check('other user cannot write library', () => bobDb.doc('users/alice/data/library').set({ routines: [] }), true);

  await check('owner can read account doc', () => aliceDb.doc('users/alice').get(), false);
  await check('owner can read private account', () => aliceDb.doc('users/alice/private/account').get(), false);
  await check('owner can read library', () => aliceDb.doc('users/alice/data/library').get(), false);
  await check('owner can write library while active', () => aliceDb.doc('users/alice/data/library').set({ routines: [{ id: 'r1' }] }), false);
  await check('anonymous owner can read own library', () => guestDb.doc('users/guest/data/library').get(), false);
  await check('anonymous owner cannot write library', () => guestDb.doc('users/guest/data/library').set({ routines: [] }), true);
  await check('anonymous owner cannot create age declaration', () => guestDb.doc('users/guest/private/account').set({
    ageDeclaration: 'at_least_14',
    ageDeclaredAt: firebase.firestore.FieldValue.serverTimestamp(),
    status: 'active',
    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
  }, { merge: true }), true);
  await check('registered owner can create age declaration', () => erinDb.doc('users/erin/private/account').set({
    ageDeclaration: 'at_least_14',
    ageDeclaredAt: firebase.firestore.FieldValue.serverTimestamp(),
    status: 'active',
    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
  }, { merge: true }), false);
  await check('owner cannot store email on users doc', () => aliceDb.doc('users/alice').update({ email: 'alice@example.com' }), true);
  await check('owner can remove legacy email from users doc', () => aliceDb.doc('users/alice').update({
    email: firebase.firestore.FieldValue.delete(),
    nickname: 'Alice',
  }), false);
  await check('owner cannot store email on public profile', () => aliceDb.doc('public_profiles/alice').set({
    nickname: 'Alice',
    email: 'alice@example.com',
  }, { merge: true }), true);
  await check('owner can update public nickname while active', () => aliceDb.doc('public_profiles/alice').set({
    nickname: 'Alice 2',
  }, { merge: true }), false);
  await check('other user cannot update public nickname', () => bobDb.doc('public_profiles/alice').set({ nickname: 'Bob' }, { merge: true }), true);

  await check('client cannot set purgeStartedAt', () => aliceDb.doc('users/alice/private/account').set({
    purgeStartedAt: firebase.firestore.FieldValue.serverTimestamp(),
  }, { merge: true }), true);
  await check('client cannot set purge_started', () => aliceDb.doc('users/alice/private/account').set({
    status: 'purge_started',
  }, { merge: true }), true);
  await check('client cannot set a one-day purgeAfter', () => aliceDb.doc('users/alice/private/account').set({
    status: 'pending_deletion',
    deletionRequestedAt: firebase.firestore.FieldValue.serverTimestamp(),
    purgeAfter: daysFromNow(1),
  }, { merge: true }), true);
  await check('client cannot set guardianConsent', () => aliceDb.doc('users/alice/private/account').set({
    guardianConsent: true,
  }, { merge: true }), true);
  await check('client cannot change ageDeclaration', () => aliceDb.doc('users/alice/private/account').set({
    ageDeclaration: 'under_14',
    ageDeclaredAt: firebase.firestore.FieldValue.serverTimestamp(),
  }, { merge: true }), true);
  await check('client timestamp is not accepted as deletionRequestedAt', () => aliceDb.doc('users/alice/private/account').set({
    status: 'pending_deletion',
    deletionRequestedAt: firebase.firestore.Timestamp.fromDate(new Date()),
    purgeAfter: daysFromNow(30),
  }, { merge: true }), true);
  await check('other user cannot request deletion', () => bobDb.doc('users/alice/private/account').set({
    status: 'pending_deletion',
    deletionRequestedAt: firebase.firestore.FieldValue.serverTimestamp(),
    purgeAfter: daysFromNow(30),
  }, { merge: true }), true);
  await check('owner can request deletion with server time and 30 days', () => aliceDb.doc('users/alice/private/account').set({
    status: 'pending_deletion',
    deletionRequestedAt: firebase.firestore.FieldValue.serverTimestamp(),
    purgeAfter: daysFromNow(30),
  }, { merge: true }), false);
  await check('second deletion request cannot move the deadline', () => aliceDb.doc('users/alice/private/account').set({
    status: 'pending_deletion',
    deletionRequestedAt: firebase.firestore.FieldValue.serverTimestamp(),
    purgeAfter: daysFromNow(30),
  }, { merge: true }), true);
  await check('pending owner cannot write library', () => aliceDb.doc('users/alice/data/library').set({ routines: [] }), true);
  await check('pending owner cannot publish a routine', () => aliceDb.doc('community_routines/pending').set({
    authorId: 'alice',
    description: 'no',
  }), true);
  await check('owner can restore before purge starts', () => aliceDb.doc('users/alice/private/account').update({
    status: 'active',
    deletionRequestedAt: firebase.firestore.FieldValue.delete(),
    purgeAfter: firebase.firestore.FieldValue.delete(),
  }), false);
  await check('owner can write library after restore', () => aliceDb.doc('users/alice/data/library').set({ routines: [{ id: 'r1' }] }), false);
  await check('purge-started owner cannot restore', () => daveDb.doc('users/dave/private/account').update({
    status: 'active',
    purgeStartedAt: firebase.firestore.FieldValue.delete(),
  }), true);
  await check('owner cannot write a deletion job', () => aliceDb.doc('deletion_jobs/alice').set({ status: 'completed' }), true);

  await check('active owner can publish a routine', () => aliceDb.doc('community_routines/post2').set({
    authorId: 'alice',
    authorName: 'Alice',
    description: 'loop',
    routine: { videoId: 'abc123xyz01', videoUrl: 'https://youtu.be/abc123xyz01' },
  }), false);
  await check('owner cannot publish as someone else', () => aliceDb.doc('community_routines/post3').set({
    authorId: 'bob',
    description: 'no',
  }), true);
  await check('anon cannot publish a routine', () => anonDb.doc('community_routines/post4').set({
    authorId: 'anon',
    description: 'no',
  }), true);
  await check('pending owner cannot publish a routine', () => caraDb.doc('community_routines/post5').set({
    authorId: 'cara',
    description: 'no',
  }), true);
  await check('other user can update only social fields', () => bobDb.doc('community_routines/post1').update({
    likedBy: ['bob'],
    likesCount: 1,
  }), false);
  await check('other user cannot delete a routine', () => bobDb.doc('community_routines/post1').delete(), true);
  await check('active author can delete own routine', () => aliceDb.doc('community_routines/post2').delete(), false);
  await check('signed-in user can write video cache', () => aliceDb.doc('cached_videos/abc123xyz01').set({ title: 'Warmup' }), false);
  await check('anon can read video cache', () => anonDb.doc('cached_videos/abc123xyz01').get(), false);

  const anonStorage = anon.storage();
  const aliceStorage = alice.storage();
  const bobStorage = bob.storage();
  const caraStorage = cara.storage();
  await check('anon can read showcase file', () => anonStorage.ref('showcase/alice/take.mp4').getMetadata(), false);
  await check('other user cannot delete showcase file', () => bobStorage.ref('showcase/alice/take.mp4').delete(), true);
  await check('other user cannot upload into showcase folder', () => bobStorage.ref('showcase/alice/evil.mp4').put(mediaBytes, { contentType: 'video/mp4' }), true);
  await check('pending owner cannot delete showcase file', () => caraStorage.ref('showcase/cara/take.mp4').delete(), true);
  await check('pending owner cannot upload showcase file', () => caraStorage.ref('showcase/cara/new.mp4').put(mediaBytes, { contentType: 'video/mp4' }), true);
  await check('active owner can upload showcase file', () => aliceStorage.ref('showcase/alice/new.mp4').put(mediaBytes, { contentType: 'video/mp4' }), false);
  await check('active owner can delete own showcase file', () => aliceStorage.ref('showcase/alice/new.mp4').delete(), false);
} finally {
  await testEnv.cleanup();
}

if (failures.length > 0) {
  console.error(`\n${failures.length} rules checks failed:`);
  for (const name of failures) console.error(`- ${name}`);
  process.exit(1);
}
console.log('\nAll local rules checks passed. This does not deploy rules and does not read production rules.');
