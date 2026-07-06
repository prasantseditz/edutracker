import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:google_sign_in/google_sign_in.dart' as gs;

/// Class to handle Google sign-in and sign-out
class FirebaseServices {
  final FirebaseAuth auth = FirebaseAuth.instance;

  // Use the aliased package type to avoid collisions with any local class named GoogleSignIn
  final gs.GoogleSignIn googleSignIn = gs.GoogleSignIn.standard();

  Future<bool> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        await auth.signInWithPopup(googleProvider);
        return true;
      } else {
        final gs.GoogleSignInAccount? googleSignInAccount = await googleSignIn.signIn();

        if (googleSignInAccount == null) {
          return false;
        }

        final gs.GoogleSignInAuthentication googleSignInAuthentication =
            await googleSignInAccount.authentication;

        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleSignInAuthentication.accessToken,
          idToken: googleSignInAuthentication.idToken,
        );

        await auth.signInWithCredential(credential);
        return true;
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('Error during Google sign-in: $e');
        print(st);
      }
      return false;
    }
  }

  Future<void> googleSignOut() async {
    try {
      await auth.signOut();
      try {
        await googleSignIn.signOut();
      } catch (_) {}
    } catch (e) {
      if (kDebugMode) print('Error during Google sign-out: $e');
    }
  }

  Future<bool> reauthenticateUser() async {
    try {
      final User? user = auth.currentUser;
      if (user == null) return false;

      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        await user.reauthenticateWithPopup(googleProvider);
        return true;
      } else {
        await googleSignIn.signOut();
        final gs.GoogleSignInAccount? googleSignInAccount = await googleSignIn.signIn();

        if (googleSignInAccount == null) {
          return false;
        }

        final gs.GoogleSignInAuthentication googleSignInAuthentication =
            await googleSignInAccount.authentication;

        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleSignInAuthentication.accessToken,
          idToken: googleSignInAuthentication.idToken,
        );

        await user.reauthenticateWithCredential(credential);
        return true;
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('Error during Google re-authentication: $e');
        print(st);
      }
      return false;
    }
  }
}
