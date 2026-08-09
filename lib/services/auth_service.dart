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
  return sha256.convert(
    utf8.encode(password),
  ).toString();
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

Future<void> setCurrentUser(
  Map<String, dynamic> user,
) async {
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
// ==========================================================

Future<Map<String, dynamic>?> loadCurrentUser() async {
  final prefs = await SharedPreferences.getInstance();

  final savedUser = prefs.getString('current_user');

  if (savedUser == null || savedUser.isEmpty) {
    currentUser = null;

    print('NO SAVED USER');

    return null;
  }

  try {
    final decoded = jsonDecode(savedUser);

    if (decoded is Map) {
      currentUser = Map<String, dynamic>.from(decoded);

      print('USER RESTORED: $currentUser');

      return currentUser;
    }
  } catch (e) {
    print('LOAD USER ERROR: $e');

    await prefs.remove('current_user');
  }

  currentUser = null;

  return null;
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

