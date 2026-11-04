.DEFAULT_GOAL := help

-include .make.local

FLUTTER ?= fvm flutter
APP_DIR := apps/marginmind
IOS_APP := build/ios/iphoneos/Runner.app
BUNDLE_ID := io.github.mylxsw.marginmind

.PHONY: help devices ios-build iphone ipad ipad-simulator android-apk

help:
	@printf '%s\n' \
	  'make devices         查看设备编号' \
	  'make iphone          构建并部署到 iPhone 真机' \
	  'make ipad            构建并部署到 iPad 真机' \
	  'make ipad-simulator  在 iPad 模拟器运行（Ctrl-C 退出）' \
	  'make android-apk     构建 Android Release APK' \
	  'make ios-build       仅构建 iOS 真机版本'

devices:
	xcrun devicectl list devices
	$(FLUTTER) devices

ios-build:
	cd $(APP_DIR) && $(FLUTTER) build ios --release

iphone:
	@test -n "$(IPHONE_ID)" || { echo '请在 .make.local 设置 IPHONE_ID，或执行 make iphone IPHONE_ID=设备编号'; exit 1; }
	$(MAKE) ios-build
	cd $(APP_DIR) && xcrun devicectl device install app --device "$(IPHONE_ID)" $(IOS_APP)
	xcrun devicectl device process launch --device "$(IPHONE_ID)" $(BUNDLE_ID)

ipad:
	@test -n "$(IPAD_ID)" || { echo '请在 .make.local 设置 IPAD_ID，或执行 make ipad IPAD_ID=设备编号'; exit 1; }
	$(MAKE) ios-build
	cd $(APP_DIR) && xcrun devicectl device install app --device "$(IPAD_ID)" $(IOS_APP)
	xcrun devicectl device process launch --device "$(IPAD_ID)" $(BUNDLE_ID)

ipad-simulator:
	@test -n "$(IPAD_SIMULATOR_ID)" || { echo '请在 .make.local 设置 IPAD_SIMULATOR_ID，或执行 make ipad-simulator IPAD_SIMULATOR_ID=设备编号'; exit 1; }
	@xcrun simctl list devices booted | grep -Fq "$(IPAD_SIMULATOR_ID)" || xcrun simctl boot "$(IPAD_SIMULATOR_ID)"
	@open -a Simulator || echo '无法打开 Simulator 窗口，请从 Xcode 打开模拟器。'
	cd $(APP_DIR) && $(FLUTTER) run -d "$(IPAD_SIMULATOR_ID)"

android-apk:
	cd $(APP_DIR) && $(FLUTTER) build apk --release
	@echo 'APK: $(APP_DIR)/build/app/outputs/flutter-apk/app-release.apk'
	@echo '注意：当前 Release APK 使用调试签名，仅供测试。'
