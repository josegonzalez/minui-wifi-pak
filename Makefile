TAG ?= latest
PAK_NAME := $(shell jq -r .label config.json)

ARCHITECTURES := arm arm64
PLATFORMS := miyoomini my282 rg35xxplus tg5040

JQ_VERSION := 1.7.1
MINUI_LIST_VERSION := 0.10.1
MINUI_KEYBOARD_VERSION := 0.5.1
MINUI_PRESENTER_VERSION := 0.6.1

clean:
	rm -f bin/*/jq || true
	rm -f bin/*/minui-keyboard || true
	rm -f bin/*/minui-list || true
	rm -f bin/*/minui-presenter || true

build: $(foreach platform,$(PLATFORMS),bin/$(platform)/minui-keyboard bin/$(platform)/minui-list bin/$(platform)/minui-presenter) $(foreach arch,$(ARCHITECTURES),bin/$(arch)/jq)

bin/arm/jq:
	mkdir -p bin/arm
	curl -f -o bin/arm/jq -sSL https://github.com/jqlang/jq/releases/download/jq-$(JQ_VERSION)/jq-linux-armhf
	curl -sSL -o bin/arm/jq.LICENSE "https://raw.githubusercontent.com/jqlang/jq/refs/heads/$(JQ_VERSION)/COPYING"

bin/arm64/jq:
	mkdir -p bin/arm64
	curl -f -o bin/arm64/jq -sSL https://github.com/jqlang/jq/releases/download/jq-$(JQ_VERSION)/jq-linux-arm64
	curl -sSL -o bin/arm64/jq.LICENSE "https://raw.githubusercontent.com/jqlang/jq/refs/heads/$(JQ_VERSION)/COPYING"

bin/%/minui-keyboard:
	mkdir -p bin/$*
	curl -f -o bin/$*/minui-keyboard -sSL https://github.com/josegonzalez/minui-keyboard/releases/download/$(MINUI_KEYBOARD_VERSION)/minui-keyboard-$*
	chmod +x bin/$*/minui-keyboard

bin/%/minui-list:
	mkdir -p bin/$*
	curl -f -o bin/$*/minui-list -sSL https://github.com/josegonzalez/minui-list/releases/download/$(MINUI_LIST_VERSION)/minui-list-$*
	chmod +x bin/$*/minui-list

bin/%/minui-presenter:
	mkdir -p bin/$*
	curl -f -o bin/$*/minui-presenter -sSL https://github.com/josegonzalez/minui-presenter/releases/download/$(MINUI_PRESENTER_VERSION)/minui-presenter-$*
	chmod +x bin/$*/minui-presenter

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	ls -lah dist
