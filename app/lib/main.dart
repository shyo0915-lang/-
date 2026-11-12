import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'data/local_database.dart';
import 'data/repository.dart';
import 'data/sample_repository.dart';
import 'data/supabase_repository.dart';
import 'services/geocoder.dart';
import 'services/maps_loader.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment;
  await prepareGoogleMaps(config.mapsApiKey);
  final database = await LocalDatabase.open();
  final AppRepository repository;
  if (config.hasSupabase) {
    await Supabase.initialize(url: config.supabaseUrl, publishableKey: config.supabaseAnonKey);
    final client = Supabase.instance.client;
    repository = SupabaseAppRepository(client, config, database);
  } else {
    repository = SampleRepository(storage: database);
  }
  await repository.init();
  final geocoder = RoutingGeocoder(
    config: config,
    accessToken: () => config.hasSupabase ? Supabase.instance.client.auth.currentSession?.accessToken : null,
  );
  runApp(FieldSalesApp(state: AppState(repo: repository, config: config, geocoder: geocoder)));
}
