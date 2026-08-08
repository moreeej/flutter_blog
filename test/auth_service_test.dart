import 'package:blog/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('auth service', () {
    test('hashPassword produces a stable hash', () {
      final hash1 = hashPassword('secret123');
      final hash2 = hashPassword('secret123');

      expect(hash1, equals(hash2));
      expect(hash1.length, greaterThan(20));
    });

    test('verifyPassword checks the stored hash', () {
      final storedHash = hashPassword('secret123');

      expect(verifyPassword(inputPassword: 'secret123', storedHash: storedHash), isTrue);
      expect(verifyPassword(inputPassword: 'wrong', storedHash: storedHash), isFalse);
    });
  });
}
