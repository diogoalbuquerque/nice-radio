// Providers for the plain platform-bridge services used by the app-level
// sync wrappers (`lib/app/platform_sync.dart`). Providers (not direct `new`)
// so tests can substitute fakes without touching real platform APIs.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/home_widget_service.dart';
import '../services/quick_actions_service.dart';
import '../services/station_artwork_service.dart';
import '../services/voice_command_service.dart';

final quickActionsServiceProvider = Provider<QuickActionsService>((ref) => QuickActionsService());

final voiceCommandServiceProvider = Provider<VoiceCommandService>((ref) => VoiceCommandService());

final homeWidgetServiceProvider = Provider<HomeWidgetService>((ref) => HomeWidgetService());

final stationArtworkServiceProvider = Provider<StationArtworkService>((ref) => StationArtworkService());
