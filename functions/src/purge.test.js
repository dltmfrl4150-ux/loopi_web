const test = require('node:test');
const assert = require('node:assert/strict');
const purge = require('./purge');

test('purge is not due before the deadline or after the lock', () => {
  const now = Date.parse('2026-05-01T00:00:00Z');
  assert.equal(purge.isPurgeDue({
    status: purge.PENDING,
    purgeAfterMs: now + 1000,
    purgeStartedAt: null,
  }, now), false);
  assert.equal(purge.isPurgeDue({
    status: purge.PENDING,
    purgeAfterMs: now,
    purgeStartedAt: null,
  }, now), true);
  assert.equal(purge.isPurgeDue({
    status: purge.PENDING,
    purgeAfterMs: now - 1,
    purgeStartedAt: 'locked',
  }, now), false);
  assert.equal(purge.isPurgeDue({
    status: 'active',
    purgeAfterMs: now - 1,
    purgeStartedAt: null,
  }, now), false);
});

test('withdrawn author id does not contain the raw uid and is stable', () => {
  const uid = 'firebaseUid1234567890abcd';
  const first = purge.withdrawnAuthorId(uid);
  const second = purge.withdrawnAuthorId(uid);
  assert.equal(first, second);
  assert.equal(first.startsWith('withdrawn_'), true);
  assert.equal(first.includes(uid), false);
  const fields = purge.anonymizedAuthorFields(uid);
  assert.equal(fields.authorNickname, '탈퇴한 회원');
  assert.equal(fields.authorPhotoUrl, null);
  assert.equal(fields.authorId, first);
});

test('showcase deletion path must belong to the owner', () => {
  const uid = 'alice';
  const owned = purge.ownedShowcaseStoragePath({
    ownerUid: uid,
    downloadUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/showcase%2Falice%2Ftake.mp4?alt=media',
  });
  assert.equal(owned, 'showcase/alice/take.mp4');
  assert.equal(purge.ownedShowcaseStoragePath({
    ownerUid: uid,
    storagePath: 'showcase/bob/take.mp4',
  }), null);
  assert.equal(purge.ownedShowcaseStoragePath({
    ownerUid: uid,
    downloadUrl: 'https://www.youtube.com/watch?v=abc',
  }), null);
  assert.equal(purge.routineReferencesUrl(new Set(['https://cdn.example/a.mp4']), 'https://cdn.example/a.mp4'), true);
});

test('job progress does not include contact or media fields', () => {
  const patch = purge.jobProgressPatch({ uid: 'alice', step: 'delete_showcase', deletedCount: 2 });
  assert.deepEqual(Object.keys(patch).sort(), ['lastDeletedCount', 'lastStep', 'status', 'uid']);
  assert.equal(JSON.stringify(patch).includes('http'), false);
  assert.equal(JSON.stringify(patch).includes('@'), false);
});
