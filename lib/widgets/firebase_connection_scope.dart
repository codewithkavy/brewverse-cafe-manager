import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../firebase_runtime_config.dart';
import '../services/server_connection.dart';

/// Place below MaterialApp.builder. Cached membership and inventory remain
/// readable, while unconfirmed connections disable sensitive UI actions.
class FirebaseConnectionScope extends StatefulWidget {
  const FirebaseConnectionScope(
      {required this.child,
      this.connection,
      this.serverConfirmation,
      this.sessions,
      this.membershipConfirmation,
      super.key});
  final Widget child;
  final ServerConnection? connection;
  // Dependency injection for previews and tests; no Firebase requests are made.
  final Stream<bool>? serverConfirmation;
  final Stream<User?>? sessions;
  final Stream<bool> Function(User user)? membershipConfirmation;
  @override
  State<FirebaseConnectionScope> createState() =>
      _FirebaseConnectionScopeState();
}

class _FirebaseConnectionScopeState extends State<FirebaseConnectionScope> {
  late final ServerConnection connection =
      widget.connection ?? ServerConnection.instance;
  StreamSubscription<User?>? _auth;
  StreamSubscription<dynamic>? _records;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    final confirmations = widget.serverConfirmation;
    if (confirmations != null) {
      connection.beginSession();
      _records = confirmations.listen(
          (live) => connection.reportSnapshot(fromCache: !live),
          onError: (_) => connection.markUnavailable());
    } else {
      // Verification/claim refresh can keep the UID while changing authorization.
      _auth = (widget.sessions ?? BrewVerseFirebaseConfig.auth.idTokenChanges())
          .listen(_session);
    }
  }

  void _session(User? user) {
    final generation = ++_generation;
    unawaited(_records?.cancel());
    _records = null;
    if (user == null) {
      connection.endSession();
      return;
    }
    connection.beginSession();
    final confirmation = widget.membershipConfirmation;
    if (confirmation != null) {
      _records = confirmation(user).listen((live) {
        if (generation == _generation) {
          connection.reportSnapshot(fromCache: !live);
        }
      }, onError: (_) {
        if (generation == _generation) connection.markUnavailable();
      });
      return;
    }
    _records = BrewVerseFirebaseConfig.firestore
        .collection('cafe_members')
        .where('uid', isEqualTo: user.uid)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (generation == _generation) {
        connection.reportSnapshot(
            fromCache: snapshot.metadata.isFromCache ||
                snapshot.metadata.hasPendingWrites);
      }
    }, onError: (_) {
      if (generation == _generation) connection.markUnavailable();
    });
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_auth?.cancel());
    unawaited(_records?.cancel());
    connection.endSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: connection,
        builder: (context, _) => Column(children: [
          if (connection.managed &&
              connection.state != ServerReadState.confirmed)
            Material(
                color: const Color(0xFFFFE7BD),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      const Icon(Icons.cloud_off_outlined,
                          size: 18, color: Color(0xFF302C25)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              connection.state == ServerReadState.checking
                                  ? 'Checking connection. Cached data is read-only.'
                                  : 'Offline or connection unconfirmed. Cached data may be out of date; changes are disabled.',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF302C25)))),
                    ]),
                  ),
                )),
          Expanded(child: widget.child),
        ]),
      );
}
