//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import desktop_multi_window
import file_picker
import screen_retriever_macos
import share_plus
import tray_manager
import window_manager

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  FlutterMultiWindowPlugin.register(with: registry.registrar(forPlugin: "FlutterMultiWindowPlugin"))
  FilePickerPlugin.register(with: registry.registrar(forPlugin: "FilePickerPlugin"))
  ScreenRetrieverMacosPlugin.register(with: registry.registrar(forPlugin: "ScreenRetrieverMacosPlugin"))
  SharePlusMacosPlugin.register(with: registry.registrar(forPlugin: "SharePlusMacosPlugin"))
  TrayManagerPlugin.register(with: registry.registrar(forPlugin: "TrayManagerPlugin"))
  WindowManagerPlugin.register(with: registry.registrar(forPlugin: "WindowManagerPlugin"))
}
