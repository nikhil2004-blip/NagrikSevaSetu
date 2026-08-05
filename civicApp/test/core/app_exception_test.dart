// test/core/app_exception_test.dart
// ─────────────────────────────────────────────────────────────
// Unit tests for the AppException class hierarchy.
//
// Tests that:
//   - Each exception carries the right default message
//   - Custom messages override the defaults
//   - toString() returns the message (used by the UI for display)
//   - All subclasses are instances of AppException (sealed class)
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:civic/core/errors/app_exception.dart';

void main() {
  group('UnauthorizedException', () {
    test('has correct default message', () {
      const e = UnauthorizedException();
      expect(e.message, 'Session expired. Please log in again.');
    });

    test('accepts a custom message', () {
      const e = UnauthorizedException('Token expired.');
      expect(e.message, 'Token expired.');
    });

    test('toString() returns the message', () {
      const e = UnauthorizedException();
      expect(e.toString(), 'Session expired. Please log in again.');
    });

    test('is an instance of AppException', () {
      expect(const UnauthorizedException(), isA<AppException>());
    });
  });

  group('ForbiddenException', () {
    test('has correct default message', () {
      const e = ForbiddenException();
      expect(e.message, 'You do not have permission to perform this action.');
    });

    test('accepts a custom message', () {
      const e = ForbiddenException('Access denied.');
      expect(e.message, 'Access denied.');
    });

    test('is an instance of AppException', () {
      expect(const ForbiddenException(), isA<AppException>());
    });
  });

  group('NotFoundException', () {
    test('has correct default message', () {
      const e = NotFoundException();
      expect(e.message, 'Resource not found.');
    });

    test('accepts a custom message', () {
      const e = NotFoundException('Complaint not found.');
      expect(e.message, 'Complaint not found.');
    });

    test('is an instance of AppException', () {
      expect(const NotFoundException(), isA<AppException>());
    });
  });

  group('ValidationException', () {
    test('stores the provided message', () {
      const e = ValidationException('Description must be at least 10 characters.');
      expect(e.message, 'Description must be at least 10 characters.');
    });

    test('toString() returns the message', () {
      const e = ValidationException('Bad input.');
      expect(e.toString(), 'Bad input.');
    });

    test('is an instance of AppException', () {
      expect(const ValidationException('Bad input'), isA<AppException>());
    });
  });

  group('ServerException', () {
    test('has correct default message', () {
      const e = ServerException();
      expect(e.message, 'Server error. Please try again later.');
    });

    test('accepts a custom message', () {
      const e = ServerException('Database is down.');
      expect(e.message, 'Database is down.');
    });

    test('is an instance of AppException', () {
      expect(const ServerException(), isA<AppException>());
    });
  });

  group('NetworkException', () {
    test('has correct default message', () {
      const e = NetworkException();
      expect(e.message, 'No internet connection. Please check your network.');
    });

    test('accepts a custom message', () {
      const e = NetworkException('Connection timed out.');
      expect(e.message, 'Connection timed out.');
    });

    test('is an instance of AppException', () {
      expect(const NetworkException(), isA<AppException>());
    });
  });

  group('UnknownException', () {
    test('has correct default message', () {
      const e = UnknownException();
      expect(e.message, 'An unexpected error occurred.');
    });

    test('accepts a custom message', () {
      const e = UnknownException('Weird bug happened.');
      expect(e.message, 'Weird bug happened.');
    });

    test('is an instance of AppException', () {
      expect(const UnknownException(), isA<AppException>());
    });
  });

  group('AppException as Exception', () {
    test('can be caught as a generic Exception', () {
      void throwsNetwork() => throw const NetworkException();
      expect(throwsNetwork, throwsA(isA<Exception>()));
    });

    test('can be caught as AppException in a try-catch', () {
      try {
        throw const UnauthorizedException('Expired');
      } on AppException catch (e) {
        expect(e.message, 'Expired');
      }
    });

    test('different subtypes caught by AppException handler', () {
      final exceptions = <AppException>[
        const UnauthorizedException(),
        const ForbiddenException(),
        const NotFoundException(),
        const ValidationException('bad'),
        const ServerException(),
        const NetworkException(),
        const UnknownException(),
      ];

      for (final e in exceptions) {
        expect(e, isA<AppException>());
        expect(e.message, isNotEmpty);
        expect(e.toString(), equals(e.message));
      }
    });
  });
}
