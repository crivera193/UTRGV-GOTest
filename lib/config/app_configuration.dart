/// New-project configuration only; no fallback to the former team's backend.
abstract final class AppConfiguration {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static bool get hasBackend =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
