import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/auth_provider.dart';
import 'providers/dashboard_provider.dart';
import 'services/app_settings_service.dart';
import 'services/supabase_service.dart';
import 'ui/structure/dashboard_screen.dart';
import 'ui/login_screen.dart';
import 'ui/setup_screen.dart';
import 'utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// URL e anon key vêm de --dart-define (ver dashboard/README.md).
/// Nunca hardcoded: evita publicar credenciais de um projeto Supabase real no repo.
const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    // Sem credenciais (build sem --dart-define): arranca em modo demonstração
    // failsafe (com banner de aviso) em vez de crashar num ecrã em branco.
    debugPrint(
      'SUPABASE_URL / SUPABASE_ANON_KEY em falta. Corre com:\n'
      '  flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...\n'
      'Ver dashboard/README.md para detalhes. A arrancar em modo demonstração.',
    );
    SupabaseService.isMockMode = true;
    SupabaseService.isFailsafeMock = true;
  } else {
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      );
      SupabaseService.supabaseReady = true;
    } catch (e) {
      // Sem rede no arranque: o failsafe de getBatches nunca chegaria a
      // correr (o initialize lançava primeiro), cai para demonstração.
      debugPrint('Supabase.initialize falhou ($e), a arrancar em modo demonstração.');
      SupabaseService.isMockMode = true;
      SupabaseService.isFailsafeMock = true;
    }
  }
  await AppSettingsService.load();
  runApp(const ProviderScope(child: AppleQualityDashboard()));
}

class CustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

class AppleQualityDashboard extends ConsumerWidget {
  const AppleQualityDashboard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider);
    AppColors.isDark = isDark;
    final user = ref.watch(authProvider);
    final isSessionActive = ref.watch(sessionActiveProvider);

    Widget homeScreen;
    if (user == null) {
      homeScreen = LoginScreen();
    } else if (!isSessionActive) {
      homeScreen = SetupScreen();
    } else {
      homeScreen = DashboardScreen();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Apple Quality Platform',
      scrollBehavior: CustomScrollBehavior(),
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: homeScreen,
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDarkTheme = brightness == Brightness.dark;
    final textPrimary = isDarkTheme ? const Color(0xFFE2F1EC) : Colors.black;
    final textSecondary = isDarkTheme ? const Color(0xFF8CA59D) : const Color(0xFF333333);
    final background = isDarkTheme ? const Color(0xFF050E0C) : const Color(0xFFF4F7F6);
    final surface = isDarkTheme ? const Color(0xFF0E1A16) : const Color(0xFFFFFFFF);
    final glassBorder = isDarkTheme ? const Color(0x1F10B981) : const Color(0x2B10B981);
    final primary = isDarkTheme ? const Color(0xFF00FFC4) : const Color(0xFF00A383);
    final accent = const Color(0xFF10B981);
    final rot = const Color(0xFFFF4D6D);

    final baseTextTheme = brightness == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: GoogleFonts.interTextTheme(
        baseTextTheme.copyWith(
          displayLarge: GoogleFonts.inter(fontWeight: FontWeight.bold, color: textPrimary),
          headlineMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textPrimary),
          bodyLarge: GoogleFonts.inter(color: textPrimary),
          bodyMedium: GoogleFonts.inter(color: textSecondary),
        ),
      ),
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: isDarkTheme ? Colors.black : Colors.white,
        secondary: accent,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        background: background,
        onBackground: textPrimary,
        error: rot,
        onError: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: glassBorder, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: glassBorder,
        thickness: 1,
        space: 24,
      ),
      useMaterial3: true,
    );
  }
}