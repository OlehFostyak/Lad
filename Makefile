# Lad: build, test, sign and install with the Command Line Tools only (no Xcode).
#
# Adapted from the CLT recipe in ~/Work/Babak/Makefile, validated on this Mac. Every variable can be
# overridden on the command line, e.g. `make bundle SIGN_ID=-`. Written for the GNU Make 3.81 that
# ships with the CLT.

NAME        ?= Lad
BUNDLE_ID   ?= dev.oleh.lad

# The package root is the directory of this Makefile, so `make -C` and `make -f` both work.
PKG         := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
RES         := $(PKG)/Resources
SCRATCH     ?= $(PKG)/.build
STAGE       := $(SCRATCH)/stage
APPDIR      := $(STAGE)/$(NAME).app
INSTALL_DIR ?= $(HOME)/Applications
INSTALLED   := $(INSTALL_DIR)/$(NAME).app
CLT         := $(shell xcode-select -p)
SDK_PATH    := $(shell xcrun --show-sdk-path 2>/dev/null)
LSREGISTER  := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
CONFIG      ?= release
SWIFT       ?= swift
PYTHON      ?= python3
FIXTURE     := $(PKG)/Tests/LadCoreTests/Fixtures/layouts.json
SYMBOL_ALLOWLIST := $(PKG)/tools/allowed-symbols.txt
# The imports the allow-list covers: every non-Swift symbol, and Foundation's Swift API (file and
# URL access such as Data(contentsOf:) or write(to:) lives there). The Swift runtime and standard
# library are left out.
# A universal binary lists each slice's imports under a header line; only symbol lines count.
IMPORTS_CHECKED := awk '/^_/ && (!/^_\$$s/ || /^_\$$s10Foundation/)'

# Extra SwiftPM flags; `SWIFTPM_FLAGS=--build-system native` is the fallback if a CLT update breaks
# the default swiftbuild engine.
SWIFTPM_FLAGS ?=
SPM          = --package-path "$(PKG)" --scratch-path "$(SCRATCH)" $(SWIFTPM_FLAGS)

# Swift Testing ships in the CLT (XCTest does not). Without an explicit plugin path, test builds
# intermittently fail to load the TestingMacros plugin; the native engine also needs the CLT
# Frameworks directory spelled out, for compiling and for the rpath.
TESTING_PLUGINS := $(CLT)/usr/lib/swift/host/plugins/testing
TEST_FLAGS   = -Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS) \
  $(if $(findstring native,$(SWIFTPM_FLAGS)),\
  -Xswiftc -F -Xswiftc $(CLT)/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib)

# `make check`: warnings are errors and concurrency checking is complete.
CHECK_FLAGS  = -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete

# swiftbuild links without SDKROOT, so the binary would record the deployment target as its SDK
# version; AppKit gates linked-on-or-after behaviour on that field, so the shipped build hands the
# linker the SDK explicitly.
LINK_SDK_FLAGS = $(if $(SDK_PATH),-Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc $(SDK_PATH))

# Signing: Lad's own self-signed "Lad Local Code Signing" identity (make setup-signing), kept in a
# separate keychain locked with a password. `bundle` unlocks it only while codesign runs, so no other
# program can sign itself as Lad and inherit Lad's Accessibility permission. The designated
# requirement is certificate-based and survives rebuilds, so the grant and the login item stay
# valid. SIGN_ID=- signs ad hoc: no key at all, but macOS forgets the grant after every build.
IDENTITY      ?= Lad Local Code Signing
SIGN_ID       ?= $(IDENTITY)
SIGN_KEYCHAIN ?= $(HOME)/Library/Keychains/lad-signing.keychain-db

# Shell snippet: the number of code-signing identities matching "$$id" (a name or a SHA-1 hash).
COUNT_IDENTITIES = security find-identity -p codesigning "$(SIGN_KEYCHAIN)" 2>/dev/null | awk -v id="$$id" \
  '/Valid identities only/ { exit } \
   index($$0, "\"" id "\"") || (length(id) == 40 && id !~ /[^0-9A-Fa-f]/ && index(toupper($$0), toupper(id))) { n++ } \
   END { print n + 0 }'

# Releases (make release, then make publish): UNIVERSAL=1 adds an Intel slice, cross-compiled with
# the CLT, to the Apple Silicon build; the app is signed like an install and packed as a zip
# (Homebrew) and a DMG (drag to Applications) in dist/.
UNIVERSAL    ?=
INTEL_TRIPLE := x86_64-apple-macosx26.0
INTEL_SPM     = --package-path "$(PKG)" --scratch-path "$(SCRATCH)/intel" $(SWIFTPM_FLAGS) -c $(CONFIG) --triple $(INTEL_TRIPLE)
VERSION       = $(shell plutil -extract CFBundleShortVersionString raw "$(RES)/Info.plist")
DIST         := $(PKG)/dist

# CFBundleVersion: the commit count once the repository has commits, otherwise a date stamp.
GIT_COUNT    = $(shell [ -e "$(PKG)/.git" ] && git -C "$(PKG)" rev-list --count HEAD 2>/dev/null)
BUILD_NUMBER ?= $(if $(GIT_COUNT),$(GIT_COUNT),$(shell date +%Y%m%d%H%M))

# `make eval` options, e.g. EVAL_FLAGS='--top 5000 --code ~/Work/Babak/Sources'.
EVAL_FLAGS  ?=

.DEFAULT_GOAL := build
.PHONY: doctor build test check coverage eval fixtures dictionaries icon symbols setup-signing bundle-check bundle \
        verify install release publish run stop restart logs uninstall clean

# Checks the machine: Swift, the Swift Testing plugins, the signing identity and ~/Applications.
doctor:
	@status=0; \
	ok()   { printf '  ok    %-9s %s\n' "$$1" "$$2"; }; \
	warn() { printf '  WARN  %-9s %s\n' "$$1" "$$2"; }; \
	fail() { printf '  FAIL  %-9s %s\n' "$$1" "$$2"; status=1; }; \
	version="$$($(SWIFT) --version 2>&1 | grep -m1 'Swift version' | sed 's/^.*\(Apple Swift\)/\1/')"; \
	if [ -n "$$version" ]; then ok swift "$$version"; else fail swift "$(SWIFT) --version failed"; fi; \
	if [ -d '$(TESTING_PLUGINS)' ]; then ok testing "$(TESTING_PLUGINS)"; \
	else fail testing "Swift Testing macro plugins missing at $(TESTING_PLUGINS)"; fi; \
	if [ '$(SIGN_ID)' = - ]; then \
	  warn signing "ad hoc (SIGN_ID=-): macOS forgets the Accessibility grant after every rebuild"; \
	else \
	  id='$(SIGN_ID)'; n="$$($(COUNT_IDENTITIES))"; \
	  case "$$n" in \
	    0) fail signing "\"$(SIGN_ID)\" not found in $(SIGN_KEYCHAIN): run make setup-signing (or SIGN_ID=- to sign ad hoc)";; \
	    1) ok signing "\"$(SIGN_ID)\"";; \
	    *) fail signing "$$n identities match \"$(SIGN_ID)\"; pass SIGN_ID=<SHA-1>";; \
	  esac; \
	fi; \
	if [ -d '$(INSTALL_DIR)' ]; then ok install "$(INSTALL_DIR) exists"; \
	else fail install "$(INSTALL_DIR) is missing: mkdir -p \"$(INSTALL_DIR)\""; fi; \
	for lang in uk en; do \
	  if [ -s "$(RES)/Dictionaries/$$lang.tsv" ]; then ok words "$$lang.tsv"; \
	  else fail words "$(RES)/Dictionaries/$$lang.tsv is missing: make dictionaries"; fi; \
	done; \
	if [ $$status -eq 0 ]; then echo "doctor: ok"; else echo "doctor: FAIL"; fi; \
	exit $$status

build:
	$(SWIFT) build $(SPM) -c $(CONFIG) $(LINK_SDK_FLAGS)

# Under swiftbuild a plain `swift test` rebuilds from scratch even right after `swift build
# --build-tests` with the same flags, so it runs the fresh products with --skip-build.
test:
	$(SWIFT) build $(SPM) --build-tests $(TEST_FLAGS)
	$(SWIFT) test $(SPM) --skip-build $(TEST_FLAGS)

check:
	$(SWIFT) build $(SPM) --build-tests $(CHECK_FLAGS) $(TEST_FLAGS)
	$(SWIFT) test $(SPM) --skip-build $(CHECK_FLAGS) $(TEST_FLAGS)

# Line coverage of LadCore (the app target is AppKit glue, checked by hand).
coverage:
	$(SWIFT) build $(SPM) --build-tests --enable-code-coverage $(TEST_FLAGS)
	$(SWIFT) test $(SPM) --skip-build --enable-code-coverage $(TEST_FLAGS)
	@set -e; \
	json="$$($(SWIFT) test $(SPM) --show-codecov-path)"; \
	dir="$$(dirname "$$json")"; \
	bin="$$(find "$(SCRATCH)" -type f \( -path '*LadCoreTests.xctest/Contents/MacOS/LadCoreTests' \
	  -o -path '*LadPackageTests.xctest/Contents/MacOS/LadPackageTests' \) | head -1)"; \
	if [ -z "$$bin" ]; then echo "error: no LadCoreTests binary under $(SCRATCH)" >&2; exit 1; fi; \
	xcrun llvm-cov report "$$bin" -instr-profile "$$dir/default.profdata" "$(PKG)/Sources/LadCore"

# The detector's quality on the bundled word lists (and on code, with EVAL_FLAGS='--code <dir>').
eval:
	$(SWIFT) run $(SPM) -c release lad-eval quality --resources "$(RES)" --fixture "$(FIXTURE)" $(EVAL_FLAGS)

# Snapshots the enabled keyboard layouts into the test fixture.
fixtures:
	$(SWIFT) run $(SPM) lad-eval dump-layouts > "$(FIXTURE).tmp"
	mv "$(FIXTURE).tmp" "$(FIXTURE)"

dictionaries:
	$(PYTHON) -I "$(PKG)/tools/build_dictionaries.py"

# Rewrites the allow-list of symbols the app may import, from a fresh release build. Review the
# diff before committing it: every new symbol is a new capability (make verify enforces the list).
symbols: build
	@bin="$$($(SWIFT) build $(SPM) -c $(CONFIG) --show-bin-path)/$(NAME)"; \
	if [ -n "$(UNIVERSAL)" ]; then \
	  $(SWIFT) build $(INTEL_SPM) --product $(NAME) $(LINK_SDK_FLAGS) >/dev/null; \
	  intel="$$($(SWIFT) build $(INTEL_SPM) --show-bin-path)/$(NAME)"; \
	else \
	  intel=""; \
	fi; \
	{ echo "# Non-Swift symbols and Swift Foundation API the Lad binary may import (make verify)."; \
	  echo "# Regenerate with make symbols and review the diff: a new symbol is a new capability."; \
	  echo "# xcrun swift-demangle < tools/allowed-symbols.txt reads the Foundation ones."; \
	  nm -u "$$bin" $$intel | $(IMPORTS_CHECKED) | LC_ALL=C sort -u; } > "$(SYMBOL_ALLOWLIST)"; \
	echo "wrote $(SYMBOL_ALLOWLIST) ($$(grep -vc '^#' "$(SYMBOL_ALLOWLIST)") symbols)"

# Once: creates the signing keychain and identity. Interactive (asks for a new password).
setup-signing:
	SIGN_KEYCHAIN="$(SIGN_KEYCHAIN)" /bin/bash "$(PKG)/tools/make_signing_identity.sh"

icon:
	@set -e; \
	set="$(RES)/AppIcon.iconset"; \
	rm -rf "$$set"; \
	$(SWIFT) "$(PKG)/tools/make_icon.swift" "$$set"; \
	iconutil -c icns "$$set" -o "$(RES)/AppIcon.icns"; \
	rm -rf "$$set"; \
	echo "wrote $(RES)/AppIcon.icns"

# Fails before the build when the icon, a word list or the signing identity is missing.
bundle-check:
	@if [ ! -f "$(RES)/AppIcon.icns" ]; then \
	  echo "error: $(RES)/AppIcon.icns is missing; run make icon" >&2; exit 1; \
	fi; \
	for lang in uk en; do \
	  if [ ! -s "$(RES)/Dictionaries/$$lang.tsv" ]; then \
	    echo "error: $(RES)/Dictionaries/$$lang.tsv is missing; run make dictionaries" >&2; exit 1; \
	  fi; \
	done; \
	if [ '$(SIGN_ID)' = - ]; then \
	  echo "warning: signing ad hoc (SIGN_ID=-): macOS forgets the Accessibility grant after every rebuild"; \
	else \
	  id='$(SIGN_ID)'; n="$$($(COUNT_IDENTITIES))"; \
	  if [ "$$n" -eq 0 ]; then \
	    echo "error: signing identity \"$(SIGN_ID)\" not found in $(SIGN_KEYCHAIN); run make setup-signing (or SIGN_ID=- to sign ad hoc)" >&2; exit 1; \
	  elif [ "$$n" -gt 1 ]; then \
	    echo "error: $$n identities match \"$(SIGN_ID)\"; pass SIGN_ID=<SHA-1>" >&2; exit 1; \
	  fi; \
	fi

# Products are located with --show-bin-path: the layout differs between build engines.
bundle: bundle-check build
	@set -e; \
	bin="$$($(SWIFT) build $(SPM) -c $(CONFIG) --show-bin-path)"; \
	app="$(APPDIR)"; \
	plutil -lint -s "$(RES)/Info.plist"; \
	rm -rf "$$app"; \
	mkdir -p "$$app/Contents/MacOS" "$$app/Contents/Resources/Dictionaries"; \
	cp "$(RES)/Info.plist" "$$app/Contents/Info.plist"; \
	plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" "$$app/Contents/Info.plist"; \
	printf 'APPL????' > "$$app/Contents/PkgInfo"; \
	if [ -n "$(UNIVERSAL)" ]; then \
	  $(SWIFT) build $(INTEL_SPM) --product $(NAME) $(LINK_SDK_FLAGS); \
	  lipo -create "$$bin/$(NAME)" "$$($(SWIFT) build $(INTEL_SPM) --show-bin-path)/$(NAME)" -output "$$app/Contents/MacOS/$(NAME)"; \
	else \
	  cp "$$bin/$(NAME)" "$$app/Contents/MacOS/$(NAME)"; \
	fi; \
	cp "$(RES)/AppIcon.icns" "$$app/Contents/Resources/AppIcon.icns"; \
	"$$bin/lad-eval" pack --resources "$(RES)" --out "$$app/Contents/Resources/Dictionaries"; \
	cp "$(RES)/Licenses.txt" "$$app/Contents/Resources/Licenses.txt"; \
	plutil -lint -s "$$app/Contents/Info.plist"; \
	if [ '$(SIGN_ID)' = - ]; then \
	  codesign --force --timestamp=none --options runtime --sign - "$$app"; \
	else \
	  trap 'security lock-keychain "$(SIGN_KEYCHAIN)" 2>/dev/null || true' EXIT; \
	  echo "Unlocking Lad's signing keychain for codesign (it locks again right after):"; \
	  security unlock-keychain "$(SIGN_KEYCHAIN)"; \
	  codesign --force --timestamp=none --options runtime --keychain "$(SIGN_KEYCHAIN)" --sign '$(SIGN_ID)' "$$app"; \
	  security lock-keychain "$(SIGN_KEYCHAIN)"; \
	fi; \
	echo "built $$app (CFBundleVersion $(BUILD_NUMBER), signed with $(SIGN_ID))"
	@$(MAKE) --no-print-directory verify

# Verifies the seal and that the designated requirement is certificate-based (not ad hoc).
verify:
	@set -e; \
	app="$(APPDIR)"; \
	codesign --verify --deep --strict "$$app"; \
	ident="$$(codesign -d -v "$$app" 2>&1 | sed -n 's/^Identifier=//p')"; \
	requirement="$$(codesign -d -r- "$$app" 2>&1 | sed -n 's/^#* *designated => //p')"; \
	printf 'verified %s\n  identifier:  %s\n  designated:  %s\n' "$$app" "$$ident" "$$requirement"; \
	if [ "$$ident" != "$(BUNDLE_ID)" ]; then echo "error: expected identifier $(BUNDLE_ID)" >&2; exit 1; fi; \
	case "$$requirement" in \
	  *certificate*) echo "  ok: certificate-based requirement";; \
	  *) if [ '$(SIGN_ID)' = - ]; then echo "  warning: ad hoc requirement changes with every build"; \
	     else echo "error: expected a certificate-based designated requirement" >&2; exit 1; fi;; \
	esac; \
	binary="$$app/Contents/MacOS/$(NAME)"; \
	for library in $$(otool -L "$$binary" | awk '/^[[:space:]]/ { print $$1 }' | LC_ALL=C sort -u); do \
	  case "$$library" in \
	    *Network.framework*|*CFNetwork*|*WebKit*|*CloudKit*|*MultipeerConnectivity*) \
	      echo "error: links $$library" >&2; exit 1;; \
	    /System/Library/Frameworks/*|/usr/lib/swift/*|/usr/lib/libSystem.B.dylib|/usr/lib/libobjc.A.dylib|/usr/lib/libc++.1.dylib) ;; \
	    *) echo "error: links $$library, outside the allow-list" >&2; exit 1;; \
	  esac; \
	done; \
	forbidden="$$(nm -u "$$binary" | grep -E '^_(socket|connect|getaddrinfo|nw_|posix_spawn|execv|execve|dlopen|CFSocket|CFReadStreamCreateForHTTPRequest)|NSURLSession|NSURLConnection' || true)"; \
	if [ -n "$$forbidden" ]; then echo "error: the binary imports $$forbidden" >&2; exit 1; fi; \
	echo "  ok: only system frameworks; no network or process-spawning symbols"; \
	allowed="$$(mktemp)"; \
	grep -v '^#' "$(SYMBOL_ALLOWLIST)" | LC_ALL=C sort -u > "$$allowed"; \
	unexpected="$$(nm -u "$$binary" | $(IMPORTS_CHECKED) | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$$allowed")"; \
	rm -f "$$allowed"; \
	if [ -n "$$unexpected" ]; then \
	  echo "error: the binary imports symbols missing from tools/allowed-symbols.txt (review them, then make symbols):" >&2; \
	  printf '  %s\n' $$unexpected >&2; exit 1; \
	fi; \
	echo "  ok: every imported symbol is on tools/allowed-symbols.txt"

# bundle → stop → ditto to Lad.app.new → swap with two renames → lsregister -f → open.
install: bundle
	@case "$(INSTALL_DIR)" in ""|/) echo "error: refusing INSTALL_DIR='$(INSTALL_DIR)'" >&2; exit 1;; esac
	@$(MAKE) --no-print-directory stop
	@old="$$(codesign -d -r- "$(INSTALLED)" 2>/dev/null | sed -n 's/^#* *designated => //p')"; \
	new="$$(codesign -d -r- "$(APPDIR)" 2>/dev/null | sed -n 's/^#* *designated => //p')"; \
	if [ -n "$$old" ] && [ "$$old" != "$$new" ]; then \
	  echo "The signature changed: macOS would keep Lad's old Accessibility entry and ignore it."; \
	  echo "Resetting it (tccutil reset Accessibility $(BUNDLE_ID)); grant Lad again when it asks."; \
	  tccutil reset Accessibility "$(BUNDLE_ID)" || true; \
	fi
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED).new" "$(INSTALLED).old"
	ditto "$(APPDIR)" "$(INSTALLED).new"
	if [ -e "$(INSTALLED)" ]; then mv "$(INSTALLED)" "$(INSTALLED).old"; fi
	mv "$(INSTALLED).new" "$(INSTALLED)"
	rm -rf "$(INSTALLED).old"
	"$(LSREGISTER)" -f "$(INSTALLED)"
	@$(MAKE) --no-print-directory run

# A release of the committed tree: the universal app signed with Lad's identity (the keychain
# password, as for install; friends' Accessibility grants follow that certificate, so a release is
# never signed ad hoc), packed in dist/ with SHA-256 sums.
release:
	@if [ '$(SIGN_ID)' = - ] && [ -z "$(ALLOW_ADHOC)" ]; then \
	  echo "error: a release must be signed with $(IDENTITY), not ad hoc" >&2; exit 1; \
	fi
	@$(MAKE) --no-print-directory bundle UNIVERSAL=1
	@set -e; \
	version="$(VERSION)"; \
	rm -rf "$(DIST)"; \
	mkdir -p "$(DIST)"; \
	ditto -c -k --keepParent "$(APPDIR)" "$(DIST)/$(NAME)-$$version.zip"; \
	staging="$$(mktemp -d)"; \
	ditto "$(APPDIR)" "$$staging/$(NAME).app"; \
	ln -s /Applications "$$staging/Applications"; \
	hdiutil create -quiet -volname "$(NAME) $$version" -srcfolder "$$staging" -ov -format UDZO "$(DIST)/$(NAME)-$$version.dmg"; \
	rm -rf "$$staging"; \
	cd "$(DIST)" && shasum -a 256 "$(NAME)-$$version.zip" "$(NAME)-$$version.dmg" > SHA256SUMS; \
	echo "Release $$version in $(DIST):"; \
	cat SHA256SUMS

# Publishes dist/ as GitHub release v$(VERSION) and points the Homebrew cask at it (tools/publish.sh).
publish:
	@/bin/bash "$(PKG)/tools/publish.sh" "$(VERSION)" "$(DIST)"

# Through LaunchServices, never the raw executable.
run:
	open "$(INSTALLED)"

# pkill, waiting up to 5 s for the exit so `restart` does not race the single-instance guard.
stop:
	@pkill -x "$(NAME)" 2>/dev/null || true; \
	i=0; \
	while pgrep -x "$(NAME)" >/dev/null 2>&1; do \
	  i=$$((i + 1)); \
	  if [ $$i -gt 50 ]; then echo "warning: $(NAME) is still running after 5 s" >&2; break; fi; \
	  sleep 0.1; \
	done

restart:
	@$(MAKE) --no-print-directory stop
	@$(MAKE) --no-print-directory run

logs:
	/usr/bin/log stream --predicate 'subsystem == "$(BUNDLE_ID)"' --level info

# Removes the installed app. The Accessibility entry stays in System Settings until removed there.
uninstall: stop
	@case "$(INSTALL_DIR)" in ""|/) echo "error: refusing INSTALL_DIR='$(INSTALL_DIR)'" >&2; exit 1;; esac
	rm -rf "$(INSTALLED)"

clean:
	@case "$(abspath $(SCRATCH))" in ""|/|"$(abspath $(HOME))"|"$(PKG)") echo "error: refusing SCRATCH='$(SCRATCH)'" >&2; exit 1;; esac
	rm -rf "$(SCRATCH)"
