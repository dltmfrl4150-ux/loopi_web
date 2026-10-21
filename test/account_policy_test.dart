import 'package:flutter_test/flutter_test.dart';
import 'package:loopi_web/account/account_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loopi_web/state/routine_library.dart';

void main() {
  test('login does not require the age self-declaration screen', () {
    expect(
      requiresAgeDeclaration(isAnonymous: true, hasAdultDeclaration: false),
      isFalse,
    );
    expect(
      requiresAgeDeclaration(isAnonymous: false, hasAdultDeclaration: false),
      isFalse,
    );
    expect(
      requiresAgeDeclaration(isAnonymous: false, hasAdultDeclaration: true),
      isFalse,
    );
  });

  test('deletion request is idempotent until purge starts', () {
    const adult = PrivateAccountState(
      exists: true,
      status: AccountPolicy.active,
      ageDeclaration: AccountPolicy.ageDeclarationAdult,
    );
    expect(AccountPolicy.deletionRequest(adult), DeletionRequestDecision.create);

    const pending = PrivateAccountState(
      exists: true,
      status: AccountPolicy.pendingDeletion,
      ageDeclaration: AccountPolicy.ageDeclarationAdult,
      purgeAfter: null,
    );
    expect(AccountPolicy.deletionRequest(pending), DeletionRequestDecision.alreadyPending);
    expect(AccountPolicy.restore(pending), RestoreDecision.allow);

    const started = PrivateAccountState(
      exists: true,
      status: AccountPolicy.purgeStarted,
      ageDeclaration: AccountPolicy.ageDeclarationAdult,
      purgeStarted: true,
    );
    expect(AccountPolicy.deletionRequest(started), DeletionRequestDecision.purgeStarted);
    expect(AccountPolicy.restore(started), RestoreDecision.purgeStarted);
  });

  test('purge does not start before the deadline', () {
    final due = DateTime.utc(2026, 5, 1);
    final account = PrivateAccountState(
      exists: true,
      status: AccountPolicy.pendingDeletion,
      ageDeclaration: AccountPolicy.ageDeclarationAdult,
      purgeAfter: due,
    );
    expect(AccountPolicy.isPurgeDue(account, due.subtract(const Duration(minutes: 1))), isFalse);
    expect(AccountPolicy.isPurgeDue(account, due), isTrue);
    expect(
      AccountPolicy.isPurgeDue(
        PrivateAccountState(
          exists: true,
          status: AccountPolicy.pendingDeletion,
          purgeAfter: due,
          purgeStarted: true,
        ),
        due.add(const Duration(days: 1)),
      ),
      isFalse,
    );
  });

  test('anonymized author fields drop the photo and keep no raw uid', () {
    const uid = 'firebaseUid1234567890abcd';
    final fields = AccountPolicy.anonymizedAuthorFields('withdrawn_abc');
    expect(fields['authorNickname'], AccountPolicy.withdrawnAuthorLabel);
    expect(fields['authorPhotoUrl'], isNull);
    expect(fields.containsKey('videoUrl'), isFalse);
    expect(fields['authorId'], isNot(uid));
    expect('${fields['authorId']}'.contains(uid), isFalse);
  });

  test('showcase storage path must belong to the owner', () {
    expect(
      ownedShowcaseStoragePath(
        ownerUid: 'alice',
        downloadUrl: 'https://firebasestorage.googleapis.com/v0/b/app/o/showcase%2Falice%2Ftake.mp4?alt=media&token=x',
      ),
      'showcase/alice/take.mp4',
    );
    expect(
      ownedShowcaseStoragePath(ownerUid: 'alice', storagePath: 'showcase/bob/take.mp4'),
      isNull,
    );
    expect(
      ownedShowcaseStoragePath(
        ownerUid: 'alice',
        downloadUrl: 'https://www.youtube.com/watch?v=abc123xyz01',
      ),
      isNull,
    );
  });

  test('local withdrawal removes only that uid', () async {
    SharedPreferences.setMockInitialValues({
      'loopi_saved_routines_u_alice': ['{"id":"r1","name":"A","videoUrl":"https://youtu.be/abc","videoId":"abc","segments":[],"createdAt":"2026-01-01T00:00:00.000Z"}'],
      'loopi_saved_routines_u_bob': ['{"id":"r2","name":"B","videoUrl":"https://youtu.be/def","videoId":"def","segments":[],"createdAt":"2026-01-01T00:00:00.000Z"}'],
      'loopi_saved_routines_device': ['{"id":"r3","name":"C","videoUrl":"https://youtu.be/ghi","videoId":"ghi","segments":[],"createdAt":"2026-01-01T00:00:00.000Z"}'],
    });
    final library = RoutineLibrary();
    await library.attachUser('alice');
    expect(library.routines.map((routine) => routine.id), ['r1']);
    await library.discardLocalAccountData('alice');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('loopi_saved_routines_u_alice'), isNull);
    expect(prefs.getStringList('loopi_saved_routines_u_bob'), isNotNull);
    expect(prefs.getStringList('loopi_saved_routines_device'), isNotNull);
    expect(library.routines, isEmpty);
  });
}
