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

  /// 地図の既定表示はGoogleマップ。
  /// 簡易地図（FallbackMap）に切り替えるときは、ビルド時に --dart-define=USE_GOOGLE_MAP=false を付ける。
  static const bool _googleMapOptIn = bool.fromEnvironment('USE_GOOGLE_MAP', defaultValue: true);
  bool get useGoogleMap => _googleMapOptIn;
  String get geocodingKey => geocodingApiKey.isNotEmpty ? geocodingApiKey : mapsApiKey;

  static const fromEnvironment = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    mapsApiKey: String.fromEnvironment('MAPS_API_KEY'),
    geocodingApiKey: String.fromEnvironment('GEOCODING_API_KEY'),
  );
}
