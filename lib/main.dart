import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'api.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/punch_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);
  await PontomaisApi.instance.loadCreds();
  runApp(const ControleHorasApp());
}

class ControleHorasApp extends StatelessWidget {
  const ControleHorasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controle de Horas',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Android 15+ força edge-to-edge: o app desenha atrás da barra de
      // navegação/status. Esse SafeArea global recua TODA tela (inclusive
      // bottom sheets e snackbars) pra fora dos insets do sistema, então cada
      // tela usa padding normal. O ColoredBox pinta a faixa da barra.
      builder: (context, child) => ColoredBox(
        color: C.bg,
        child: SafeArea(child: child!),
      ),
      home: PontomaisApi.instance.loggedIn
          ? const PunchScreen()
          : const LoginScreen(),
    );
  }
}
