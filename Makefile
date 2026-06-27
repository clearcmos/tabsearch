BUILD_DIR = .build/release
APP_BUNDLE = TabSearch.app

# Stable self-signed code-signing identity (in the login keychain). Signing with a constant
# identity keeps the app's signature - and therefore its TCC grants (Accessibility,
# Automation) - stable across rebuilds, instead of the churn an ad-hoc signature causes.
# To recreate it, see CLAUDE.md ("Code signing"). Falls back to ad-hoc if absent.
SIGN_IDENTITY = tabsearch-codesign

all: cli app

cli:
	swift build -c release --product tabsearch

app:
	swift build -c release --product TabSearchBar

debug:
	swift build --product tabsearch
	swift build --product TabSearchBar

# Create the .app bundle for the menu bar app.
bundle: app
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(BUILD_DIR)/TabSearchBar $(APP_BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	@if security find-identity -p codesigning | grep -q "$(SIGN_IDENTITY)"; then \
		echo "codesign: $(SIGN_IDENTITY)"; \
		codesign --force --deep --sign "$(SIGN_IDENTITY)" $(APP_BUNDLE); \
	else \
		echo "codesign: '$(SIGN_IDENTITY)' not found, using ad-hoc (TCC grants will not persist across rebuilds)"; \
		codesign --force --deep --sign - $(APP_BUNDLE); \
	fi

install-cli: cli
	cp $(BUILD_DIR)/tabsearch /usr/local/bin/

install-app: bundle
	cp -R $(APP_BUNDLE) /Applications/

# One-shot for a fresh machine: build, install to /Applications, and launch the app so it
# fires the Accessibility/Automation prompts. Then enable "Launch at Login" from its menu.
setup: install-app
	open /Applications/$(APP_BUNDLE)

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)

.PHONY: all cli app debug bundle install-cli install-app setup clean
