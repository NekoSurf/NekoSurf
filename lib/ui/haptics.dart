import 'package:flutter/services.dart';

/// The light tick felt when something's kept or let go: a board favorited,
/// a thread bookmarked, a file saved. Called where it's tapped, not in the
/// models, which also change when iCloud sync brings changes from elsewhere.
void keepFeedback() => HapticFeedback.lightImpact();
