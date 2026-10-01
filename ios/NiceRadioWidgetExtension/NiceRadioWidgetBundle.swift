import SwiftUI
import WidgetKit

// The extension's own entry point (its Info.plist's NSExtensionPrincipalClass
// points here automatically once this replaces Xcode's auto-generated
// bundle file). Just
// one widget, so a WidgetBundle of one is slightly more ceremony than a
// bare `@main struct NiceRadioWidget: Widget` would need — kept anyway
// because it's WidgetKit's own standard shape and is the type Xcode's
// "Widget Extension" template itself generates, which keeps this file
// close to what anyone opening the target for the first time already
// expects to see.
@main
struct NiceRadioWidgetBundle: WidgetBundle {
  var body: some Widget {
    NiceRadioWidget()
  }
}
