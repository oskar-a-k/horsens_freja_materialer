import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Set<String> _adminOverrideEmails = {
    'materialer@horsensfreja.dk',
  };

  late final Future<_UserAccess> _userAccessFuture;

  @override
  void initState() {
    super.initState();
    _userAccessFuture = _loadUserAccess();
  }

  Future<_UserAccess> _loadUserAccess() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const _UserAccess(isAdmin: false, role: 'guest', permissions: []);
    }

    final currentEmail = currentUser.email?.toLowerCase();
    final bool hasOverrideAdmin =
        currentEmail != null && _adminOverrideEmails.contains(currentEmail);

    final userDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid);

    // Use cache first so the page can display quickly on repeated visits.
    DocumentSnapshot<Map<String, dynamic>>? snapshot;
    try {
      snapshot = await userDoc.get(const GetOptions(source: Source.cache));
      // ignore: avoid_print
      print(
        'Cache read for user ${currentUser.uid}: exists=${snapshot.exists}',
      );
    } on FirebaseException catch (e) {
      // ignore: avoid_print
      print('Cache read failed for user ${currentUser.uid}: ${e.message}');
      snapshot = null;
    }

    if (snapshot != null && snapshot.exists) {
      final bool isAdmin = snapshot.data()?['isAdmin'] as bool? ?? false;
      final String role =
          snapshot.data()?['role'] as String? ?? (isAdmin ? 'admin' : 'viewer');
      final permissions = List<String>.from(
        snapshot.data()?['permissions'] as List<dynamic>? ??
            _defaultPermissionsForRole(role),
      );

      if (hasOverrideAdmin && !isAdmin) {
        return const _UserAccess(
          isAdmin: true,
          role: 'admin',
          permissions: ['hold', 'laegetasker', 'lager', 'mangelliste'],
        );
      }

      return _UserAccess(
        isAdmin: isAdmin,
        role: role,
        permissions: permissions,
      );
    }

    try {
      // Try server fetch but keep it short so UI doesn't hang.
      // ignore: avoid_print
      print('Fetching user document from server for ${currentUser.uid}');
      snapshot = await userDoc.get().timeout(const Duration(seconds: 8));
      // ignore: avoid_print
      print(
        'Server fetch completed for ${currentUser.uid}: exists=${snapshot.exists}',
      );
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' ||
          (e.message?.toLowerCase().contains('client is offline') ?? false)) {
        // Firestore not reachable — return a safe fallback so UI can continue.
        // ignore: avoid_print
        print(
          'Firestore unavailable (${e.code}): ${e.message}. Returning fallback access.',
        );
        final bool isAdminFallback = hasOverrideAdmin;
        final String roleFallback = isAdminFallback ? 'admin' : 'viewer';
        final permissionsFallback = _defaultPermissionsForRole(roleFallback);
        return _UserAccess(
          isAdmin: isAdminFallback,
          role: roleFallback,
          permissions: permissionsFallback,
        );
      }
      rethrow;
    } on TimeoutException catch (e) {
      // Server did not respond in time — provide a fallback to keep UI responsive.
      // ignore: avoid_print
      print('Server request timed out: $e. Returning fallback access.');
      final bool isAdminFallback = hasOverrideAdmin;
      final String roleFallback = isAdminFallback ? 'admin' : 'viewer';
      final permissionsFallback = _defaultPermissionsForRole(roleFallback);
      return _UserAccess(
        isAdmin: isAdminFallback,
        role: roleFallback,
        permissions: permissionsFallback,
      );
    }

    if (snapshot.exists) {
      final bool isAdmin = snapshot.data()?['isAdmin'] as bool? ?? false;
      final String role =
          snapshot.data()?['role'] as String? ?? (isAdmin ? 'admin' : 'viewer');
      final permissions = List<String>.from(
        snapshot.data()?['permissions'] as List<dynamic>? ??
            _defaultPermissionsForRole(role),
      );

      if (hasOverrideAdmin && !isAdmin) {
        await userDoc.set({
          'isAdmin': true,
          'role': 'admin',
          'permissions': _defaultPermissionsForRole('admin'),
        }, SetOptions(merge: true));

        return const _UserAccess(
          isAdmin: true,
          role: 'admin',
          permissions: ['hold', 'laegetasker', 'lager', 'mangelliste'],
        );
      }

      return _UserAccess(
        isAdmin: isAdmin,
        role: role,
        permissions: permissions,
      );
    }

    final usersCollection = FirebaseFirestore.instance.collection('users');
    bool isAdmin = hasOverrideAdmin;
    if (!hasOverrideAdmin) {
      try {
        // ignore: avoid_print
        print('Checking for existing admins in users collection');
        final existingAdmins = await usersCollection
            .where('isAdmin', isEqualTo: true)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 8));
        isAdmin = existingAdmins.docs.isEmpty;
        // ignore: avoid_print
        print('Existing admins check completed: foundAdmin=${!isAdmin}');
      } on TimeoutException catch (e) {
        // ignore: avoid_print
        print('Existing admins query timed out: $e — defaulting to non-admin');
        isAdmin = false;
      }
    }

    final String role = isAdmin ? 'admin' : 'viewer';
    final permissions = _defaultPermissionsForRole(role);

    await userDoc.set({
      'email': currentUser.email,
      'isAdmin': isAdmin,
      'role': role,
      'permissions': permissions,
    }, SetOptions(merge: true));

    return _UserAccess(isAdmin: isAdmin, role: role, permissions: permissions);
  }

  static List<String> _defaultPermissionsForRole(String role) {
    switch (role) {
      case 'admin':
      case 'manager':
        return ['hold', 'laegetasker', 'lager', 'mangelliste'];
      case 'coach':
        return ['hold', 'mangelliste'];
      case 'viewer':
      default:
        return ['hold'];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Horsens Freja Materialer'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.secondary.withAlpha((0.9 * 255).round()),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              child: const Text('Log ud'),
            ),
          ),
          FutureBuilder<_UserAccess>(
            future: _userAccessFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isAdmin != true) {
                return const SizedBox.shrink();
              }

              return IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Indstillinger',
                onPressed: () => Navigator.pushNamed(context, '/settings'),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 110,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.network(
                          'icons/logo.png',
                          height: 62,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.sports_soccer,
                            size: 44,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Horsens Freja Materialer',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FutureBuilder<_UserAccess>(
                  future: _userAccessFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Tjekker adgang...'),
                      );
                    }

                    if (snapshot.hasError) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: _ErrorInfoCard(
                          label: 'Fejl ved indlæsning af adgang',
                          message: snapshot.error.toString(),
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Ingen adgangsdata fundet.'),
                      );
                    }

                    final access = snapshot.data!;
                    final roleText = 'Rolle: ${access.role}';
                    final pageText = 'Sider: ${access.permissions.join(', ')}';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          roleText,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pageText,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                FutureBuilder<_UserAccess>(
                  future: _userAccessFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: _ErrorInfoCard(
                          label: 'Fejl ved indlæsning af sider',
                          message: snapshot.error.toString(),
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Center(
                        child: Text('Ingen adgangsdata fundet.'),
                      );
                    }

                    final access = snapshot.data!;
                    final allowedPages = _pageDefinitions
                        .where((page) => access.permissions.contains(page.code))
                        .toList();

                    if (allowedPages.isEmpty) {
                      return const Center(
                        child: Text('Ingen sider er tildelt til din bruger.'),
                      );
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = constraints.maxWidth >= 1000
                            ? 4
                            : constraints.maxWidth >= 720
                            ? 3
                            : 2;
                        final childAspectRatio = constraints.maxWidth >= 1000
                            ? 1.2
                            : 1.0;

                        return GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: childAspectRatio,
                          children: allowedPages
                              .map(
                                (page) => _NavigationCard(
                                  title: page.title,
                                  icon: page.icon,
                                  routeName: page.route,
                                ),
                              )
                              .toList(),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String routeName;

  const _NavigationCard({
    required this.title,
    required this.icon,
    required this.routeName,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, routeName),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserAccess {
  final bool isAdmin;
  final String role;
  final List<String> permissions;

  const _UserAccess({
    required this.isAdmin,
    required this.role,
    required this.permissions,
  });
}

class _ErrorInfoCard extends StatelessWidget {
  final String label;
  final String message;

  const _ErrorInfoCard({required this.label, required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Kopiér fejl'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onErrorContainer,
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: message));
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Fejl kopieret til udklipsholder'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageDefinition {
  final String code;
  final String title;
  final IconData icon;
  final String route;

  const _PageDefinition({
    required this.code,
    required this.title,
    required this.icon,
    required this.route,
  });
}

const List<_PageDefinition> _pageDefinitions = [
  _PageDefinition(
    code: 'hold',
    title: 'Hold',
    icon: Icons.people,
    route: '/hold',
  ),
  _PageDefinition(
    code: 'laegetasker',
    title: 'Lægetasker',
    icon: Icons.medical_services,
    route: '/laegetasker',
  ),
  _PageDefinition(
    code: 'lager',
    title: 'Lager',
    icon: Icons.inventory_2,
    route: '/lager',
  ),
  _PageDefinition(
    code: 'mangelliste',
    title: 'Mangelliste',
    icon: Icons.report_problem,
    route: '/mangelliste',
  ),
];
