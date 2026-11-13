import AppKit

/// Builds the application menu.
///
/// Without one AppKit has nothing bound to Cmd-Q or Cmd-W, and the command bar
/// gets no clipboard shortcuts, since those are dispatched as menu key
/// equivalents rather than plain key events.
@MainActor
enum MainMenu {
    static func install(into app: NSApplication) {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenu())
        mainMenu.addItem(editMenu())
        mainMenu.addItem(viewMenu())

        let window = windowMenu()
        mainMenu.addItem(window)
        app.windowsMenu = window.submenu

        app.mainMenu = mainMenu
    }

    private static func applicationMenu() -> NSMenuItem {
        let menu = NSMenu()

        menu.addItem(
            withTitle: L("Hide Vimba"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )

        let hideOthers = menu.addItem(
            withTitle: L("Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]

        menu.addItem(
            withTitle: L("Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: L("Quit Vimba"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        return wrap(menu, titled: L("Vimba"))
    }

    private static func editMenu() -> NSMenuItem {
        let menu = NSMenu(title: L("Edit"))

        // All of these are dispatched down the responder chain to whichever
        // text field is editing, rather than to a fixed target.
        menu.addItem(
            withTitle: L("Undo"),
            action: #selector(UndoActions.undo(_:)),
            keyEquivalent: "z"
        )
        menu.addItem(
            withTitle: L("Redo"),
            action: #selector(UndoActions.redo(_:)),
            keyEquivalent: "Z"
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: L("Select All"),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        return wrap(menu, titled: L("Edit"))
    }

    private static func viewMenu() -> NSMenuItem {
        let menu = NSMenu(title: L("View"))

        menu.addItem(
            withTitle: L("Zoom In"),
            action: #selector(ZoomActions.zoomIn(_:)),
            keyEquivalent: "+"
        )
        menu.addItem(
            withTitle: L("Zoom Out"),
            action: #selector(ZoomActions.zoomOut(_:)),
            keyEquivalent: "-"
        )
        menu.addItem(
            withTitle: L("Actual Size"),
            action: #selector(ZoomActions.zoomReset(_:)),
            keyEquivalent: "0"
        )

        return wrap(menu, titled: L("View"))
    }

    private static func windowMenu() -> NSMenuItem {
        let menu = NSMenu(title: L("Window"))

        menu.addItem(
            withTitle: L("Close Window"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        menu.addItem(
            withTitle: L("Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        menu.addItem(.separator())

        let fullScreen = menu.addItem(
            withTitle: L("Enter Full Screen"),
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreen.keyEquivalentModifierMask = [.control, .command]

        return wrap(menu, titled: L("Window"))
    }

    private static func wrap(_ menu: NSMenu, titled title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// AppKit declares no symbol for the undo and redo responder actions, so they
/// are named here purely to build type-checked selectors.
@objc private protocol UndoActions {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}

/// Zoom actions travel the responder chain to the window controller, so they
/// are named here only to build type-checked selectors.
@objc private protocol ZoomActions {
    func zoomIn(_ sender: Any?)
    func zoomOut(_ sender: Any?)
    func zoomReset(_ sender: Any?)
}
