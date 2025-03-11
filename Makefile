TAG ?= latest
PAK_NAME := $(shell jq -r .label config.json)

PLATFORMS := rg35xxplus tg5040
MINUI_LIST_VERSION := 0.6.0
MINUI_KEYBOARD_VERSION := 0.4.0

clean:
	rm -f bin/jq-arm || true
	rm -f bin/jq-arm64 || true
	rm -f bin/minui-keyboard-* || true
	rm -f bin/minui-list-* || true
	rm -f bin/sdl2imgshow || true
	rm -f res/fonts/BPreplayBold.otf || true

build: $(foreach platform,$(PLATFORMS),bin/minui-keyboard-$(platform) bin/minui-list-$(platform)) bin/jq-arm bin/jq-arm64 bin/sdl2imgshow res/fonts/BPreplayBold.otf

bin/jq-arm:
	curl -f -o bin/jq-arm -sSL https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-armhf

bin/jq-arm64:
	curl -f -o bin/jq-arm64 -sSL https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-arm64

bin/minui-keyboard-%:
	curl -f -o bin/minui-keyboard-$* -sSL https://github.com/josegonzalez/minui-keyboard/releases/download/$(MINUI_KEYBOARD_VERSION)/minui-keyboard-$*
	chmod +x bin/minui-keyboard-$*

bin/minui-list-%:
	curl -f -o bin/minui-list-$* -sSL https://github.com/josegonzalez/minui-list/releases/download/$(MINUI_LIST_VERSION)/minui-list-$*
	chmod +x bin/minui-list-$*

bin/sdl2imgshow:
	docker buildx build --platform linux/arm64 --load -f Dockerfile.sdl2imgshow --progress plain -t app/sdl2imgshow:$(TAG) .
	docker container create --name extract app/sdl2imgshow:$(TAG)
	docker container cp extract:/go/src/github.com/kloptops/sdl2imgshow/build/sdl2imgshow bin/sdl2imgshow
	docker container rm extract
	chmod +x bin/sdl2imgshow

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	ls -lah dist

res/fonts/BPreplayBold.otf:
	mkdir -p res/fonts
	curl -f -sSL -o res/fonts/BPreplayBold.otf "https://raw.githubusercontent.com/shauninman/MinUI/refs/heads/main/skeleton/SYSTEM/res/BPreplayBold-unhinted.otf"
