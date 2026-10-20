/// Verifies mailbox format, not current student enrollment.
abstract final class StudentEmail {
  static final _pattern = RegExp(
    r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+edu$",
    caseSensitive: false,
  );
  static bool isEligible(String value) => _pattern.hasMatch(value.trim());
}
