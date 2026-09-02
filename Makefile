.PHONY: all build install uninstall clean icon run

all: build

build:
	@bash scripts/build.sh

install:
	@bash install.sh

uninstall:
	@bash uninstall.sh

icon:
	@bash scripts/generate-icon.sh

run: build
	@open "dist/DeepSeek Harness.app"

clean:
	@rm -rf dist build /tmp/dsh_app_icon.iconset
	@echo "Cleaned build artifacts."
