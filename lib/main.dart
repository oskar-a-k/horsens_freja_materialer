import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:horsens_freja_materialer_web/firebase_options.dart';
import 'package:horsens_freja_materialer_web/pages/home_page.dart';
import 'package:horsens_freja_materialer_web/pages/hold_page.dart';
import 'package:horsens_freja_materialer_web/pages/laegetasker_page.dart';
import 'package:horsens_freja_materialer_web/pages/lager_page.dart';
import 'package:horsens_freja_materialer_web/pages/login_page.dart';
import 'package:horsens_freja_materialer_web/pages/mangelliste_page.dart';
import 'package:horsens_freja_materialer_web/pages/settings_page.dart';
import 'package:horsens_freja_materialer_web/services/firestore_inventory_service.dart';
import 'package:horsens_freja_materialer_web/services/inventory_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    // ignore: avoid_print
    print('Firestore persistence enabled');
  } catch (e) {
    // Log the error but continue — persistence is optional on some browsers.
    // ignore: avoid_print
    print('Failed to enable Firestore persistence: $e');
  }
  final firestore = FirebaseFirestore.instance;
  final inventoryService = FirestoreInventoryService(firestore: firestore);
  runApp(MyApp(inventoryService: inventoryService));
}

class MyApp extends StatelessWidget {
  final InventoryService inventoryService;

  const MyApp({super.key, required this.inventoryService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Materialforvalter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData) {
            return HomePage();
          }

          return const LoginPage();
        },
      ),
      routes: {
        '/hold': (context) => HoldPage(service: inventoryService),
        '/laegetasker': (context) => LaegetaskerPage(service: inventoryService),
        '/lager': (context) => LagerPage(service: inventoryService),
        '/mangelliste': (context) => const MangellistePage(),
        '/settings': (context) => const SettingsPage(),
      },
    );
  }
}
