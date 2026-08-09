import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic>? currentUserSession;

void setCurrentUser(Map<String, dynamic>? user) {
  if (user == null) {
    currentUserSession = null;
    debugPrint('currentUser: null');
    return;
  }

  currentUserSession = Map<String, dynamic>.from(user)..remove('password');
  debugPrint('currentUser: $currentUserSession');
}

void clearCurrentUser() {
  currentUserSession = null;
  debugPrint('currentUser: null');
}

String hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

bool verifyPassword({
  required String inputPassword,
  required String storedHash,
}) {
  return hashPassword(inputPassword) == storedHash;
}

Future<Map<String, dynamic>?> fetchUserForLogin({
  required String email,
  required String password,
}) async {
  final response = await Supabase.instance.client
      .from('users')
      .select()
      .eq('email', email)
      .limit(1)
      .maybeSingle();

  if (response == null) {
    return null;
  }

  final storedHash = response['password'] as String?;
  if (storedHash == null) {
    return null;
  }

  final isValid = verifyPassword(
    inputPassword: password,
    storedHash: storedHash,
  );

  if (!isValid) {
    return null;
  }

  return response;
}