//
//  AssetCommands.swift
//  Assets
//
//  Menu commands routed to the focused catalog document via FocusedValues
//

import AppKit
import SwiftUI

// MARK: - Asset Document Actions

struct AssetDocumentActions {
  var hasSelection: Bool
  var copy: () -> Void
  var copyName: () -> Void
  var selectAll: () -> Void
  var exportAll: () -> Void
  var exportSelected: () -> Void
  var focusSearch: () -> Void
}

extension FocusedValues {
  @Entry var assetActions: AssetDocumentActions?
}

// MARK: - Asset Menu Commands

struct AssetMenuCommands: Commands {
  @FocusedValue(\.assetActions) private var actions

  var body: some Commands {
    CommandGroup(after: .importExport) {
      Button("Export All…") {
        actions?.exportAll()
      }
      .keyboardShortcut("e", modifiers: [.command, .shift])
      .disabled(actions == nil)

      Button("Export Selected…") {
        actions?.exportSelected()
      }
      .keyboardShortcut("e", modifiers: .command)
      .disabled(actions?.hasSelection != true)
    }

    CommandGroup(replacing: .pasteboard) {
      // Cut/Paste always route to the text first responder; they no-op
      // harmlessly when no text field is focused.
      Button("Cut") {
        NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
      }
      .keyboardShortcut("x", modifiers: .command)

      // Always enabled: disabling on hasSelection would kill text copy
      // while typing in search (.disabled can't see the first responder).
      Button("Copy") {
        if NSApp.keyWindow?.firstResponder is NSTextView {
          NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        } else {
          actions?.copy()
        }
      }
      .keyboardShortcut("c", modifiers: .command)

      Button("Copy Name") {
        actions?.copyName()
      }
      .keyboardShortcut("c", modifiers: [.command, .option])
      .disabled(actions?.hasSelection != true)

      Button("Paste") {
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
      }
      .keyboardShortcut("v", modifiers: .command)

      Divider()

      Button("Select All") {
        if NSApp.keyWindow?.firstResponder is NSTextView {
          NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        } else {
          actions?.selectAll()
        }
      }
      .keyboardShortcut("a", modifiers: .command)
    }

    CommandGroup(replacing: .textEditing) {
      Button("Find") {
        actions?.focusSearch()
      }
      .keyboardShortcut("f", modifiers: .command)
      .disabled(actions == nil)
    }
  }
}
