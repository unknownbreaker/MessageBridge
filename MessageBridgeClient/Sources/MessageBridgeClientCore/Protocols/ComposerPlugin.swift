import SwiftUI

/// Protocol for plugins that add features to the message compose area.
///
/// Plugins can provide toolbar buttons and respond to activation
/// (toolbar tap or keyboard shortcut). Register plugins in
/// `ComposerRegistry` at app launch.
public protocol ComposerPlugin: Identifiable, Sendable {
    var id: String { get }
    var icon: String { get }
    var keyboardShortcut: KeyEquivalent? { get }
    var modifiers: EventModifiers { get }

    /// Whether this plugin should show a toolbar button.
    func showsToolbarButton(context: any ComposerContext) -> Bool

    /// Handle activation (toolbar tap or keyboard shortcut).
    @MainActor func activate(context: any ComposerContext) async
}

/// The interface plugins use to interact with the composer.
@MainActor
public protocol ComposerContext: AnyObject {
    var text: String { get set }
    var attachments: [DraftAttachment] { get set }

    func insertText(_ text: String)
    func addAttachment(_ attachment: DraftAttachment)
    func removeAttachment(_ id: String)
    func presentSheet(_ view: AnyView)
    func dismissSheet()
    func send() async
}

/// Events from the text editor that determine send vs newline behavior.
public enum SubmitEvent: Sendable {
    case enter
    case shiftEnter
    case optionEnter
    case commandEnter
}
