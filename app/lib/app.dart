import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'state/app_state.dart';
import 'ui/login_page.dart';
import 'ui/map_page.dart';

class FieldSalesApp extends StatefulWidget {
  const FieldSalesApp({super.key, required this.state});
  final AppState state;

  @override
  State<FieldSalesApp> createState() => _FieldSalesAppState();
}

class _FieldSalesAppState extends State<FieldSalesApp> {
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onChange);
    widget.state.bootstrap();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = widget.state.repo.sampleMode || widget.state.repo.session != null;
    return MaterialApp(
      title: '顧客マップ',
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 17, height: 1.35),
          bodyMedium: TextStyle(fontSize: 16, height: 1.35),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 56), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
      ),
      home: signedIn ? MapPage(state: widget.state) : LoginPage(state: widget.state),
    );
  }
}
