import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../sync/sync_engine.dart';

enum _Choice { signInAgain, remove }

/// Asks what to do when a different account signed in while this device
/// still has changes from the previous one that were never uploaded
/// ([SyncEngine.accountSwitch]). Signing back in to the previous account
/// uploads them; removing them needs a second confirmation. Nothing is
/// deleted unless the user confirms.
Future<void> askAboutPreviousAccountChanges(
    BuildContext context, SyncEngine sync) async {
  while (context.mounted) {
    final AccountSwitch? pending = sync.accountSwitch;
    if (pending == null) return;
    final String who = pending.previousAccount.isEmpty
        ? 'the account used before'
        : pending.previousAccount;
    final String changes = _changes(pending.pendingChanges);

    final _Choice? choice = await showDialog<_Choice>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Changes not uploaded yet'),
        content: Text(
          'This device has $changes from $who that '
          "haven't been uploaded.\n\n"
          'Sign in to $who to upload them first. They are kept on this '
          'device until you decide.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Choice.remove),
            child: const Text('Remove them'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(_Choice.signInAgain),
            child: Text(pending.previousAccount.isEmpty
                ? 'Sign in again'
                : 'Sign in to $who'),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null) return;

    if (choice == _Choice.signInAgain) {
      await context.read<AuthService>().signInAgainAs(pending.previousAccount);
      return;
    }

    final bool? sure = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Remove ${_changes(pending.pendingChanges)}?'),
        content: const Text(
          'They were never uploaded, so they will be lost for good. This '
          "device will then show only the signed-in account's medicines.",
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep them'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (sure == true) {
      await sync.discardPreviousAccountChanges();
      return;
    }
    // Not sure: ask again.
  }
}

String _changes(int n) => n == 1 ? '1 change' : '$n changes';
