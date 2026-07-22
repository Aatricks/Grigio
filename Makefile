SHELL := /bin/zsh

.PHONY: test build bundle spike-bundle runtime-check clean

test:
	swift run GrayscaleCoreContractTests

build:
	swift build

bundle:
	swift build -c release --product grayscale-auto
	@bin_dir="$$(swift build -c release --show-bin-path)"; \
	app="$(CURDIR)/build/grayscale-auto.app"; \
	rm -rf "$$app"; \
	mkdir -p "$$app/Contents/MacOS"; \
	install -m 755 "$$bin_dir/grayscale-auto" "$$app/Contents/MacOS/grayscale-auto"; \
	install -m 644 "$(CURDIR)/Resources/GrayscaleAuto-Info.plist" "$$app/Contents/Info.plist"; \
	codesign --force --deep --sign - "$$app"

spike-bundle:
	swift build -c release --product OverlaySpike
	@bin_dir="$$(swift build -c release --show-bin-path)"; \
	app="$(CURDIR)/build/OverlaySpike.app"; \
	rm -rf "$$app"; \
	mkdir -p "$$app/Contents/MacOS"; \
	install -m 755 "$$bin_dir/OverlaySpike" "$$app/Contents/MacOS/OverlaySpike"; \
	install -m 644 "$(CURDIR)/Resources/OverlaySpike-Info.plist" "$$app/Contents/Info.plist"; \
	codesign --force --deep --sign - "$$app"

runtime-check:
	./scripts/runtime-check.sh 60

clean:
	swift package clean
	rm -rf "$(CURDIR)/build"
