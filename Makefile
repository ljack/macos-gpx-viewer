APP = Trace
SAMPLE ?= /Users/jarkko/Downloads/saaksi-lauri-2026-09-14/lauri-nuorgamista-2026-09-14.gpx

.PHONY: project debug run release install publish clean

project:
	xcodegen generate

debug: project
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Debug -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- build | grep -E "error|warning: |BUILD" || true

run: debug
	open -a "$(PWD)/build/DerivedData/Build/Products/Debug/$(APP).app" "$(SAMPLE)"

release:
	./Scripts/build.sh

install:
	./Scripts/build.sh --install

publish:
	./Scripts/release.sh --publish

clean:
	rm -rf build $(APP).xcodeproj
