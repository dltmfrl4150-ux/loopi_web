/**
 * Pure helpers for the scheduled account purge.
 * Firebase Admin is not imported here so the decisions can be tested without
 * a deployed project or a billing plan.
 */
const crypto = require('node:crypto');

const PENDING = 'pending_deletion';
const PURGE_STARTED = 'purge_started';
const WITHDRAWN_LABEL = '탈퇴한 회원';

function withdrawnAuthorId(uid) {
  const digest = crypto.createHash('sha256').update(String(uid)).digest('hex').slice(0, 24);
  return `withdrawn_${digest}`;
}

function isPurgeDue(account, serverNowMs) {
  if (!account || account.status !== PENDING) return false;
  if (account.purgeStartedAt) return false;
  if (!account.purgeAfterMs && account.purgeAfterMs !== 0) return false;
  return serverNowMs >= account.purgeAfterMs;
}

function anonymizedAuthorFields(uid) {
  const withdrawnId = withdrawnAuthorId(uid);
  return {
    authorId: withdrawnId,
    authorName: WITHDRAWN_LABEL,
    authorNickname: WITHDRAWN_LABEL,
    authorPhotoUrl: null,
    routineAuthorId: withdrawnId,
    routineAuthorName: WITHDRAWN_LABEL,
  };
}

function ownedShowcaseStoragePath({ ownerUid, storagePath, downloadUrl }) {
  if (!ownerUid) return null;
  const direct = cleanOwnedPath(storagePath, ownerUid);
  if (direct) return direct;
  return cleanOwnedPath(pathFromDownloadUrl(downloadUrl), ownerUid);
}

function cleanOwnedPath(raw, ownerUid) {
  if (typeof raw !== 'string') return null;
  const path = raw.trim();
  if (!path || path.includes('..') || path.includes('://')) return null;
  const prefix = `showcase/${ownerUid}/`;
  if (!path.startsWith(prefix) || path.length <= prefix.length) return null;
  return path;
}

function pathFromDownloadUrl(downloadUrl) {
  if (typeof downloadUrl !== 'string' || !downloadUrl.trim()) return null;
  let uri;
  try {
    uri = new URL(downloadUrl);
  } catch (_) {
    return null;
  }
  const parts = uri.pathname.split('/').filter(Boolean);
  const marker = parts.indexOf('o');
  if (marker < 0 || marker + 1 >= parts.length) return null;
  return decodeURIComponent(parts[marker + 1]);
}

function routineReferencesUrl(routineUrls, candidateUrl) {
  if (!candidateUrl) return false;
  return routineUrls.has(candidateUrl);
}

/**
 * Job records keep the account id so a failed purge can resume.
 * They must not store email, tokens, or media URLs.
 */
function jobProgressPatch({ uid, step, deletedCount }) {
  return {
    uid,
    status: 'running',
    lastStep: step,
    lastDeletedCount: deletedCount ?? 0,
  };
}

const PURGE_STEPS = [
  'lock',
  'anonymize_routines',
  'scrub_social',
  'delete_showcase',
  'delete_avatars',
  'delete_library',
  'delete_public_profile',
  'delete_user_doc',
  'delete_auth',
  'delete_private_account',
];

module.exports = {
  PENDING,
  PURGE_STARTED,
  WITHDRAWN_LABEL,
  PURGE_STEPS,
  withdrawnAuthorId,
  isPurgeDue,
  anonymizedAuthorFields,
  ownedShowcaseStoragePath,
  routineReferencesUrl,
  jobProgressPatch,
};
