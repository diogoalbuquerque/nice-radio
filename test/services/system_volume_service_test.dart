// SystemVolumeService talks to a real platform channel that has no
// handler registered in a plain `flutter test` run (there is no phone to
// ask "what is the system volume"). These tests exercise exactly the
// fallback behavior that matters because of that: every call must
// degrade quietly to a safe default instead of throwing and taking the
// rest of the app down with it — see the class's own WHY comment for the
// full reasoning (this is not web-specific; it is what happens on *any*
// platform/environment without the plugin wired up, which includes this
// test suite).
import 'package:flutter_test/flutter_test.dart';
import 'package:nice_radio/services/system_volume_service.dart';

void main() {
  // volume_controller's `addListener` touches an EventChannel, which
  // (unlike a plain MethodChannel call) needs the test binding
  // initialized *before* it is used, or the binding check itself throws
  // — asynchronously, after `listen()` has already returned — which no
  // try/catch inside SystemVolumeService could ever catch. This is the
  // standard fix, not a workaround specific to this service.
  TestWidgetsFlutterBinding.ensureInitialized();

  late SystemVolumeService service;

  setUp(() {
    service = SystemVolumeService();
  });

  test('getVolumePercent falls back instead of throwing', () async {
    expect(await service.getVolumePercent(), isA<int>());
  });

  test('stepVolume does not throw', () async {
    await expectLater(service.stepVolume(1), completes);
  });

  test('stepOnScale moves one notch, snapping and clamping', () {
    expect(SystemVolumeService.stepOnScale(0.5, 1, 16), 9 / 16);
    expect(SystemVolumeService.stepOnScale(0.5, -1, 16), 7 / 16);
    expect(SystemVolumeService.stepOnScale(0.52, 1, 16), 9 / 16); // off-notch snaps first
    expect(SystemVolumeService.stepOnScale(1.0, 1, 16), 1.0);
    expect(SystemVolumeService.stepOnScale(0.0, -1, 16), 0.0);
  });

  test('listen does not throw, even though nothing will ever call back', () {
    expect(() => service.listen((_) {}), returnsNormally);
  });

  test('dispose does not throw when nothing was ever listening', () async {
    await expectLater(service.dispose(), completes);
  });
}
