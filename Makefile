.PHONY: build app dmg install run clean

build:
	swift build -c release

app:
	./Scripts/build_app.sh

dmg:
	./Scripts/build_dmg.sh

install:
	./Scripts/install.sh

run:
	open "dist/净卸.app"

clean:
	swift package clean
	rm -rf dist build
