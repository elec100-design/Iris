/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * CameraAccessApp.swift
 * Main entry point for the CameraAccess sample app demonstrating the Meta Wearables DAT SDK.
 */

import AppIntents
import Foundation
import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

@main
struct TurboMetaApp: App {
  #if DEBUG
  // Debug menu for simulating device connections during development
  @StateObject private var debugMenuViewModel = DebugMenuViewModel(mockDeviceKit: MockDeviceKit.shared)
  #endif
  
  #if targetEnvironment(simulator)
  @StateObject private var mockConnectionManager = MockConnectionManager()
  #endif
  
  private let wearables: WearablesInterface
  @StateObject private var wearablesViewModel: WearablesViewModel

  init() {
    // 1. Wearables SDK 환경 설정
    do {
      try Wearables.configure()
      print("✅ [TurboMeta] Wearables SDK configured successfully")
    } catch {
      print("❌ [TurboMeta] Wearables.configure() failed: \(error) | \(error.localizedDescription)")
    }
    
    // 🌟 [수정 포인트] 누락되었던 씽글톤 인스턴스 및 뷰모델 강제 초기화 (2번째 에러 완벽 해결)
    let sharedWearables = Wearables.shared
    self.wearables = sharedWearables
    self._wearablesViewModel = StateObject(wrappedValue: WearablesViewModel(wearables: sharedWearables))
  }

  var body: some Scene {
    WindowGroup {
      // Main app view with access to the shared Wearables SDK instance
      MainAppView(wearables: Wearables.shared, viewModel: wearablesViewModel)
        #if targetEnvironment(simulator)
        .environment(\.connectionManager, mockConnectionManager)
        #endif
        // Show error alerts for view model failures
        .alert("Error", isPresented: $wearablesViewModel.showError) {
          Button("OK") {
            wearablesViewModel.dismissError()
          }
        } message: {
          Text(wearablesViewModel.errorMessage)
        }

      RegistrationView(viewModel: wearablesViewModel)
    }
  }
}
