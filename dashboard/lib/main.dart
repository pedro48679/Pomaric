import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/auth_provider.dart';
import 'providers/dashboard_provider.dart';
import 'ui/dashboard_screen.dart';
import 'ui/login_screen.dart';
import 'ui/setup_screen.dart';
import 'utils/constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://albjvtpmwdbhuwmuvmam.supabase.co',
    anonKey: 'sb_publishable_UFL10M-yas8hJBS8O75qhA_w9KuEImV',
  );
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
    final user = ref.watch(authProvider);
    final isSessionActive = ref.watch(sessionActiveProvider);

    Widget homeScreen;
    if (user == null) {
      homeScreen = const LoginScreen();
    } else if (!isSessionActive) {
      homeScreen = const SetupScreen();
    } else {
      homeScreen = const DashboardScreen();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Apple Quality Platform',
      scrollBehavior: CustomScrollBehavior(),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        canvasColor: AppColors.background,
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme.copyWith(
            displayLarge: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            headlineMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            bodyLarge: GoogleFonts.inter(color: AppColors.textPrimary),
            bodyMedium: GoogleFonts.inter(color: AppColors.textSecondary),
          ),
        ),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
          background: AppColors.background,
          error: AppColors.rot,
          onSurface: AppColors.textPrimary,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.glassBorder, width: 1),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.glassBorder,
          thickness: 1,
          space: 24,
        ),
        useMaterial3: true,
      ),
      home: homeScreen,
    );
  }
}
