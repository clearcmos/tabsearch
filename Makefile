BUILD_DIR = .build/release
APP_BUNDLE = TabSearch.app

all: cli app

cli:
	swift build -c release --product tabsearch

app:
	swift build -c release --product TabSearchBar

debug:
	swift build --product tabsearch
	swift build --product TabSearchBar

# Create the .app bundle for the menu bar app (ad-hoc signed).
bundle: app
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(BUILD_DIR)/TabSearchBar $(APP_BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	codesign --force --deep --sign - $(APP_BUNDLE)

install-cli: cli
	cp $(BUILD_DIR)/tabsearch /usr/local/bin/

install-app: bundle
	cp -R $(APP_BUNDLE) /Applications/

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)

.PHONY: all cli app debug bundle install-cli install-app clean
