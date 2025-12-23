import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chat/chat_home.dart';
import '../chat/search_user_screen.dart';
import '../call/calls_page.dart';
import '../settings/settings_page.dart';
import 'watch_party_page.dart';
import 'app_bottom_nav_bar.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0; // 0: Dashboard, 1: Calls, 2: Settings, 3: Watch Party

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: IndexedStack(
        index: _index,
        children: const [
          // ChatHome without FAB; FAB is controlled by root scaffold for notch
          ChatHome(showFab: false),
          CallsPage(),
          SettingsPage(),
          WatchPartyPage(),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _index,
        onTabSelected: (i) => setState(() => _index = i),
      ),
      floatingActionButton: IgnorePointer(
        ignoring: _index != 0,
        child: AnimatedOpacity(
          opacity: _index == 0 ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: FloatingActionButton(
            heroTag: 'chat-fab',
            backgroundColor: cs.primary,
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            child: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SearchUserScreen(),
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}