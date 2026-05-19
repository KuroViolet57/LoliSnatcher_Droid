import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';

void main() {
  group('StringExtras', () {
    group('capitalizeFirst', () {
      test('should capitalize the first letter of a lowercase string', () {
        expect('hello'.capitalizeFirst, 'Hello');
      });

      test('should keep the first letter capitalized if it already is', () {
        expect('Hello'.capitalizeFirst, 'Hello');
      });

      test('should handle empty strings', () {
        expect(''.capitalizeFirst, '');
      });

      test('should handle single character strings', () {
        expect('a'.capitalizeFirst, 'A');
        expect('A'.capitalizeFirst, 'A');
      });
    });

    group('toTitleCase', () {
      test('should capitalize the first letter of each word', () {
        expect('hello world'.toTitleCase(), 'Hello World');
      });

      test('should handle already capitalized words', () {
        expect('Hello World'.toTitleCase(), 'Hello World');
      });

      test('should handle mixed case words', () {
        expect('hElLo wOrLd'.toTitleCase(), 'HElLo WOrLd');
      });

      test('should handle empty strings', () {
        expect(''.toTitleCase(), '');
      });
    });

    group('toCamelCase', () {
      test('should capitalize each word and join them (currently behaves like PascalCase)', () {
        expect('hello world'.toCamelCase(), 'HelloWorld');
      });

      test('should handle single words', () {
        expect('hello'.toCamelCase(), 'Hello');
      });
    });

    group('toSnakeCase', () {
      test('should replace spaces with underscores and lowercase the string', () {
        expect('Hello World'.toSnakeCase(), 'hello_world');
      });

      test('should handle multiple spaces', () {
        expect('hello   world'.toSnakeCase(), 'hello___world');
      });
    });

    group('toKebabCase', () {
      test('should replace spaces with hyphens and lowercase the string', () {
        expect('Hello World'.toKebabCase(), 'hello-world');
      });

      test('should handle multiple spaces', () {
        expect('hello   world'.toKebabCase(), 'hello---world');
      });
    });

    group('toPascalCase', () {
      test('should capitalize each word and join them', () {
        expect('hello world'.toPascalCase(), 'HelloWorld');
      });
    });

    group('toBool', () {
      test('should return true for "true"', () {
        expect('true'.toBool(), isTrue);
      });

      test('should return true for "1"', () {
        expect('1'.toBool(), isTrue);
      });

      test('should return false for other strings', () {
        expect('false'.toBool(), isFalse);
        expect('0'.toBool(), isFalse);
        expect('yes'.toBool(), isFalse);
        expect(''.toBool(), isFalse);
      });
    });

    group('regexpEscape', () {
      test('should escape special regex characters', () {
        expect(r'.*+?^${}()|[]\'.regexpEscape(), r'\.\*\+\?\^\$\{\}\(\)\|\[\]\\');
      });

      test('should return the same string if no special characters are present', () {
        expect('hello'.regexpEscape(), 'hello');
      });
    });
  });
}
