class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.mapsApiKey,
    required this.geocodingApiKey,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String mapsApiKey;
  final String geocodingApiKey;

  bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  bool get hasMaps => mapsApiKey.isNotEmpty;
  String get geocodingKey => geocodingApiKey.isNotEmpty ? geocodingApiKey : mapsApiKey;

  static const fromEnvironment = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    mapsApiKey: String.fromEnvironment('MAPS_API_KEY'),
    geocodingApiKey: String.fromEnvironment('GEOCODING_API_KEY'),
  );
}
