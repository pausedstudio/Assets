//
//  CoreAnimationView.swift
//  Assets
//
//  Main view for previewing Core Animation archives and bundles
//

import SwiftUI

struct CoreAnimationView: View {
  @Binding var document: CoreAnimationDocument

  @State private var _selectedStateIndex: Int? = nil
  @State private var _states: [Any] = []
  @State private var _transitionSpeed: Double = 1.0
  @State private var _isPlaying = true
  @State private var _wasPlayingBeforeScrub = false
  @State private var _scrubTime: Double = 0.0
  @State private var _animationDuration: Double = 1.0
  @State private var _autoCycleStates = true
  @State private var _cycleInterval: Double = 1.0

  var body: some View {
    HStack(spacing: 0) {
      if let package = document.package {
        VStack(spacing: 0) {
          CAMLView(
            package: package,
            selectedStateIndex: $_selectedStateIndex,
            availableStates: $_states,
            transitionSpeed: $_transitionSpeed,
            isPlaying: $_isPlaying,
            scrubTime: $_scrubTime,
            animationDuration: $_animationDuration
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)

          Divider()
          _controls
        }
      } else {
        Text("Unable to load Core Animation file")
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      }

      Divider()

      List {
        _stateRow(index: nil)
        ForEach(_states.indices, id: \.self) { _stateRow(index: $0) }
      }
      .listStyle(.sidebar)
      .frame(width: 230)
    }
    .background(Color(nsColor: .controlBackgroundColor))
    .task(id: _autoCycleStates ? _cycleInterval : -1) {
      guard _autoCycleStates, !_states.isEmpty else { return }

      while !Task.isCancelled {
        let ns = UInt64(_cycleInterval * 1_000_000_000)
        try? await Task.sleep(nanoseconds: ns)
        guard !Task.isCancelled else { break }
        if let current = _selectedStateIndex {
          _selectedStateIndex =
            current + 1 < _states.count
            ? current + 1
            : nil
        } else {
          _selectedStateIndex = 0
        }
      }
    }
  }

  @ViewBuilder
  private var _controls: some View {
    VStack(spacing: 8) {
      HStack(spacing: 6) {
        Text(_timeString(_scrubTime))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 44, alignment: .trailing)

        Slider(value: $_scrubTime, in: 0...max(_animationDuration, 0.001)) { editing in
          if editing {
            _wasPlayingBeforeScrub = _isPlaying
            _isPlaying = false
          } else if _wasPlayingBeforeScrub {
            _isPlaying = true
          }
        }

        Text(_timeString(_animationDuration))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 44, alignment: .leading)
      }

      HStack(spacing: 0) {
        Button {
          _scrubTime = 0
        } label: {
          Image(systemName: "backward.end.fill")
            .frame(width: 32, height: 24)
        }
        .buttonStyle(.plain)

        Button {
          _isPlaying.toggle()
        } label: {
          Image(systemName: _isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 36, height: 24)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])

        Spacer()

        HStack(spacing: 4) {
          Image(systemName: "gauge.with.needle")
            .foregroundStyle(.secondary)
          Slider(value: $_transitionSpeed, in: 0...2)
            .frame(width: 90)
          Text(String(format: "%.1fx", _transitionSpeed))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .leading)
        }
      }

      if !_states.isEmpty {
        Divider()
        HStack(spacing: 8) {
          Toggle("Cycle states", isOn: $_autoCycleStates)
            .toggleStyle(.switch)
            .controlSize(.small)

          if _autoCycleStates {
            Slider(value: $_cycleInterval, in: 0.25...10)
            Text(String(format: "%.1fs", _cycleInterval))
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
              .frame(width: 34, alignment: .leading)
          }

          Spacer()
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.regularMaterial)
  }

  private func _timeString(_ t: Double) -> String {
    guard t.isFinite else { return "0:00" }
    let s = Int(t)
    let cs = Int((t - Double(s)) * 100)
    return String(format: "%d:%02d", s, cs)
  }

  private func _caStateName(_ state: Any) -> String? {
    (state as? NSObject)?.value(forKey: "name") as? String
  }

  @ViewBuilder
  private func _stateRow(index: Int?) -> some View {
    Button(action: { _selectedStateIndex = index }) {
      VStack(alignment: .leading, spacing: 2) {
        if let i = index {
          Text("State \(i+1)")
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .font(.subheadline)

          HStack {
            Text(_caStateName(_states[i]) ?? "State \(i+1)")
            if _selectedStateIndex == i {
              Spacer()
              Image(systemName: "checkmark")
            }
          }
        } else {
          Text("State 0")
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .font(.subheadline)

          HStack {
            Text("Default")
            if _selectedStateIndex == nil {
              Spacer()
              Image(systemName: "checkmark")
            }
          }
        }
      }
      .padding(6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        _selectedStateIndex == index
          ? Color.accentColor.opacity(0.3)
          : Color.clear
      )
      .contentShape(.rect)
      .cornerRadius(6)
    }
    .buttonStyle(.plain)
    .listRowInsets(.init())
  }
}
