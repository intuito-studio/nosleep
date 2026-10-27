.PHONY: build debug app run stop test verify verify-lid release icon clean

build:
	swift build -c release

debug:
	swift build

app:
	@./Scripts/bundle.sh release

# Rebuild, replace the running instance, relaunch.
run: stop
	@APP=$$(./Scripts/bundle.sh debug) && open "$$APP"

# SIGTERM is routed through a normal quit, so this still switches sleep back
# on if the running app had switched it off.
stop:
	@pkill -x NoSleep || true

test:
	swift test

# Against the real system: sudo rule, timer, quit, crash backstop, energy. ~3 min.
verify:
	@./Scripts/verify.sh

# Same, with the lid closed for two minutes when asked.
verify-lid:
	@./Scripts/verify.sh lid

# Universal build → dist/NoSleep.dmg, and the cask in ../homebrew-tap updated to match.
release:
	@./Scripts/release.sh

# Redraws the icon's layers from CatGlyph.swift.
icon:
	@mkdir -p .build
	swiftc -parse-as-library Sources/NoSleep/CatGlyph.swift Scripts/make-icon.swift -o .build/make-icon
	.build/make-icon Resources/AppIcon.icon/Assets

clean:
	swift package clean
	rm -rf .build/NoSleep.app dist
