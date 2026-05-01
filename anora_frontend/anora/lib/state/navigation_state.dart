import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Write an integer page index to this provider to request a navigation
/// jump from the AppShell. The AppShell clears the request after handling it.
final navRequestProvider = StateProvider<int?>((ref) => null);
