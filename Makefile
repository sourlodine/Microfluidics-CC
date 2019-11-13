PIP ?= python -m pip
CMAKE_FLAGS ?= ""

build:
	mkdir -p build/
	(cd build/ && cmake ${CMAKE_FLAGS} ../)
	$(MAKE) -C build/
	cd ..

# https://stackoverflow.com/questions/1871549/determine-if-python-is-running-inside-virtualenv
# The --user argument is given only if we are not inside a virtualenv.
install: build
	$(PIP) install . $(shell python -c "import sys; hasattr(sys, 'real_prefix') or print('--user')") --upgrade

# This only compiles and overwrites the already installed `.so` file. It skips
# the `cmake` step and shortens the long `pip install . --upgrade` step. This
# won't detect new files or any changes to `.py` files.
compile_and_copy:
	(cd build && make -j $(JOBS))
	cp $(shell python -c "import os, mirheo; p = mirheo._libmirheo_file; print(os.path.join('build', os.path.basename(p)), p)")

uninstall:
	$(PIP) uninstall mirheo

docs:
	make -C docs/

test: install
	(cd tests && mir.make test)

clean:; rm -rf build

.PHONY: install uninstall build test clean docs
