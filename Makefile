all: build

build:
	swift build

run: build
	./.build/debug/LiquidTerminal

clean:
	swift package clean

release:
	swift build -c release

bundle: release
	rm -rf LiquidTerminal.app
	mkdir -p LiquidTerminal.app/Contents/MacOS
	mkdir -p LiquidTerminal.app/Contents/Resources
	cp .build/release/LiquidTerminal LiquidTerminal.app/Contents/MacOS/LiquidTerminal
	cp icon.icns LiquidTerminal.app/Contents/Resources/AppIcon.icns
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > LiquidTerminal.app/Contents/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> LiquidTerminal.app/Contents/Info.plist
	@echo '<plist version="1.0">' >> LiquidTerminal.app/Contents/Info.plist
	@echo '<dict>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <key>CFBundleExecutable</key>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <string>LiquidTerminal</string>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <key>CFBundleIdentifier</key>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <string>com.jorge.LiquidTerminal</string>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <key>CFBundleName</key>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <string>LiquidTerminal</string>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <key>CFBundlePackageType</key>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <string>APPL</string>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <key>CFBundleIconFile</key>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <string>AppIcon</string>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <key>LSMinimumSystemVersion</key>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <string>10.15</string>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <key>NSHighResolutionCapable</key>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '    <true/>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '</dict>' >> LiquidTerminal.app/Contents/Info.plist
	@echo '</plist>' >> LiquidTerminal.app/Contents/Info.plist
	@echo "App Bundle created at LiquidTerminal.app"
