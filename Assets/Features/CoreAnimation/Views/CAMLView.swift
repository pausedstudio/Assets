//
//  CAMLView.swift
//  Assets
//
//  NSViewRepresentable that renders a CAPackage layer tree with playback controls
//

import QuartzCore
import SwiftUI

struct CAMLView: NSViewRepresentable {
  let package: CAPackage

  @Binding var selectedStateIndex: Int?
  @Binding var availableStates: [Any]
  @Binding var transitionSpeed: Double
  @Binding var isPlaying: Bool
  @Binding var scrubTime: Double
  @Binding var animationDuration: Double

  func makeNSView(context: Context) -> CAMLContainerView {
    let container = CAMLContainerView()
    container.wantsLayer = true

    guard let rootLayer = package.rootLayer else {
      return container
    }

    rootLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    if package.isGeometryFlipped {
      rootLayer.setValue(true, forKey: "geometryFlipped")
    }

    container.layer?.addSublayer(rootLayer)
    container.rootLayer = rootLayer

    let stateController = CAStateController(layer: rootLayer)
    stateController!.setInitialStatesOfLayer(rootLayer, transitionSpeed: 0.0)

    context.coordinator.stateController = stateController
    context.coordinator.rootLayer = rootLayer

    DispatchQueue.main.async {
      if let states = rootLayer.value(forKey: "states") as? [Any] {
        self.availableStates = states
      }
      self.animationDuration = rootLayer.duration > 0 ? rootLayer.duration : 1.0
    }

    return container
  }

  func updateNSView(_ nsView: CAMLContainerView, context: Context) {
    guard
      let controller = context.coordinator.stateController,
      let layer = context.coordinator.rootLayer
    else { return }

    let coordinator = context.coordinator

    coordinator.onScrubTick = { [animationDuration] time in
      guard isPlaying else { return }
      let clamped = min(time, animationDuration)
      scrubTime = clamped
      if clamped >= animationDuration {
        isPlaying = false
      }
    }

    let effectiveTransitionSpeed = layer.speed == 0 ? 0 : Float(transitionSpeed)
    if let index = selectedStateIndex, index >= 0, index < availableStates.count {
      controller.setState(
        availableStates[index], ofLayer: layer, transitionSpeed: effectiveTransitionSpeed)
    } else if selectedStateIndex == nil {
      controller.setState(nil, ofLayer: layer, transitionSpeed: effectiveTransitionSpeed)
    }

    if isPlaying {
      let externalSeek =
        coordinator.wasPlaying && abs(scrubTime - coordinator.lastKnownScrubTime) > 0.05
      let speedChanged =
        coordinator.wasPlaying && transitionSpeed != coordinator.lastKnownTransitionSpeed

      if !coordinator.wasPlaying || externalSeek || speedChanged {
        coordinator.hasEngagedPlayback = true

        let resumeTime: Double
        if speedChanged && !externalSeek {
          resumeTime = layer.convertTime(CACurrentMediaTime(), from: nil)
          DispatchQueue.main.async {
            scrubTime = resumeTime
          }
        } else {
          resumeTime = scrubTime
        }

        let speed = Float(transitionSpeed)
        layer.speed = speed
        layer.timeOffset = 0.0
        layer.beginTime =
          speed > 0
          ? CACurrentMediaTime() - resumeTime / Double(speed)
          : CACurrentMediaTime()

        if !coordinator.wasPlaying {
          coordinator.wasPlaying = true
          coordinator.startScrubTimer()
        }
      }
    } else {
      if coordinator.wasPlaying {
        coordinator.wasPlaying = false
        coordinator.stopScrubTimer()
      }
      if coordinator.hasEngagedPlayback {
        layer.speed = 0
        layer.timeOffset = scrubTime
      }
    }

    coordinator.lastKnownScrubTime = scrubTime
    coordinator.lastKnownTransitionSpeed = transitionSpeed
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  class Coordinator {
    var stateController: CAStateController?
    var rootLayer: CALayer?
    var wasPlaying = false
    var hasEngagedPlayback = false
    var lastKnownScrubTime: Double = 0
    var lastKnownTransitionSpeed: Double = 1.0
    var onScrubTick: ((Double) -> Void)?
    private var _timer: Timer?

    func startScrubTimer() {
      _timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
        guard let self, let layer = rootLayer else { return }
        let t = layer.convertTime(CACurrentMediaTime(), from: nil)
        DispatchQueue.main.async {
          self.onScrubTick?(t)
        }
      }
    }

    func stopScrubTimer() {
      _timer?.invalidate()
      _timer = nil
    }

    deinit {
      stopScrubTimer()
    }
  }
}
