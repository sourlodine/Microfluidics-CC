PIP ?= pip
CMAKE_FLAGS ?= ""

build:
	mkdir -p build/
	(cd build/;	cmake ${CMAKE_FLAGS} ../)
	make -C build/ -j
	cd ..

install: build
	$(PIP) install . --user --upgrade

uninstall:
	$(PIP) uninstall udevicex

docs:
	make -C docs/

test: install
	(cd tests; udx.make test)

clean:; rm -rf build

.PHONY: install uninstall build test clean docs
