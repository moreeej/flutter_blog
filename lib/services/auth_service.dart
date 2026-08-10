import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ==========================================================
// CURRENT USER
// ==========================================================

Map<String, dynamic>? currentUser;

// ==========================================================
// HASH PASSWORD
// ==========================================================

String hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

// ==========================================================
// LOGIN
// ==========================================================

Future<Map<String, dynamic>?> fetchUserForLogin({
  required String email,
  required String password,
}) async {
  final hashedPassword = hashPassword(password);

  final response = await Supabase.instance.client
      .from('users')
      .select()
      .eq('email', email)
      .eq('password', hashedPassword)
      .maybeSingle();

  if (response == null) {
    return null;
  }

  return Map<String, dynamic>.from(response);
}

// ==========================================================
// SAVE CURRENT USER
// ==========================================================

Future<void> setCurrentUser(Map<String, dynamic> user) async {
  currentUser = Map<String, dynamic>.from(user);

  final prefs = await SharedPreferences.getInstance();

  await prefs.setString(
    'current_user',
    jsonEncode(currentUser),
  );

  print('USER SAVED: $currentUser');
}

// ==========================================================
// LOAD CURRENT USER
//
// Loads the cached user first, then gets the latest
// username/profile_pic/etc. from Supabase.
// ==========================================================

Future<Map<String, dynamic>?> loadCurrentUser() async {
  final prefs = await SharedPreferences.getInstance();

  // ========================================================
  // STEP 1: GET SAVED USER
  // ========================================================

  final savedUser = prefs.getString('current_user');

  if (savedUser == null || savedUser.isEmpty) {
    currentUser = null;

    print('NO SAVED USER');

    return null;
  }

  // ========================================================
  // STEP 2: DECODE SAVED USER
  // ========================================================

  try {
    final decoded = jsonDecode(savedUser);

    if (decoded is! Map) {
      currentUser = null;

      await prefs.remove('current_user');

      return null;
    }

    final Map<String, dynamic> cachedUser =
        Map<String, dynamic>.from(decoded);

    final dynamic userId = cachedUser['id'];

    if (userId == null) {
      currentUser = null;

      await prefs.remove('current_user');

      print('SAVED USER HAS NO ID');

      return null;
    }

    // ======================================================
    // STEP 3: GET LATEST USER FROM SUPABASE
    // ======================================================

    print('LOADING LATEST USER FROM SUPABASE...');

    final response = await Supabase.instance.client
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();

    // ======================================================
    // USER NO LONGER EXISTS
    // ======================================================

    if (response == null) {
      currentUser = null;

      await prefs.remove('current_user');

      print('USER DOES NOT EXIST ANYMORE');

      return null;
    }

    // ======================================================
    // STEP 4: UPDATE CURRENT USER
    // ======================================================

    currentUser = Map<String, dynamic>.from(response);

    // ======================================================
    // STEP 5: SAVE LATEST USER LOCALLY
    // ======================================================

    await prefs.setString(
      'current_user',
      jsonEncode(currentUser),
    );

    print('USER RESTORED FROM SUPABASE: $currentUser');

    print(
      'LATEST USERNAME: ${currentUser?['username']}',
    );

    print(
      'LATEST PROFILE PIC: ${currentUser?['profile_pic']}',
    );

    return currentUser;
  } on PostgrestException catch (e) {
    print('LOAD CURRENT USER SUPABASE ERROR');
    print('Message: ${e.message}');
    print('Code: ${e.code}');
    print('Details: ${e.details}');
    print('Hint: ${e.hint}');

    // ======================================================
    // FALLBACK TO CACHED USER
    //
    // If Supabase temporarily fails, we can still use
    // the locally saved user.
    // ======================================================

    try {
      final decoded = jsonDecode(savedUser);

      if (decoded is Map) {
        currentUser = Map<String, dynamic>.from(decoded);

        print('USING CACHED USER');

        return currentUser;
      }
    } catch (e) {
      print('CACHE RESTORE ERROR: $e');
    }

    currentUser = null;

    return null;
  } catch (e) {
    print('LOAD CURRENT USER ERROR: $e');

    // ======================================================
    // FALLBACK TO CACHED USER
    // ======================================================

    try {
      final decoded = jsonDecode(savedUser);

      if (decoded is Map) {
        currentUser = Map<String, dynamic>.from(decoded);

        print('USING CACHED USER');

        return currentUser;
      }
    } catch (e) {
      print('CACHE RESTORE ERROR: $e');
    }

    currentUser = null;

    return null;
  }
}

// ==========================================================
// REFRESH CURRENT USER
//
// Use this after editing username/profile_pic.
// ==========================================================

Future<Map<String, dynamic>?> refreshCurrentUser() async {
  if (currentUser == null || currentUser!['id'] == null) {
    print('NO CURRENT USER TO REFRESH');

    return null;
  }

  final dynamic userId = currentUser!['id'];

  try {
    final response = await Supabase.instance.client
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (response == null) {
      print('USER NOT FOUND');

      return null;
    }

    currentUser = Map<String, dynamic>.from(response);

    // Save latest information locally
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'current_user',
      jsonEncode(currentUser),
    );

    print('CURRENT USER REFRESHED');
    print('USERNAME: ${currentUser?['username']}');
    print('PROFILE PIC: ${currentUser?['profile_pic']}');

    return currentUser;
  } on PostgrestException catch (e) {
    print('REFRESH USER SUPABASE ERROR');
    print('Message: ${e.message}');
    print('Code: ${e.code}');
    print('Details: ${e.details}');
    print('Hint: ${e.hint}');

    return null;
  } catch (e) {
    print('REFRESH USER ERROR: $e');

    return null;
  }
}

// ==========================================================
// LOGOUT
// ==========================================================

Future<void> logoutUser() async {
  currentUser = null;

  final prefs = await SharedPreferences.getInstance();

  await prefs.remove('current_user');

  print('USER LOGGED OUT');
}