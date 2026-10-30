SHELL := /bin/sh
PYTHON ?= python3
VERSION := $(shell cat VERSION)
DIST := dist/kindlexiping261030-v$(VERSION)

.PHONY: all content preview images test serve package install release clean

all: test preview

content:
	$(PYTHON) tools/build_content.py

preview:
	$(PYTHON) tools/render.py

images:
	rm -rf build/images
	mkdir -p build/images
	@i=0; while [ $$i -lt 8 ]; do $(PYTHON) tools/render_worker.py $$i 8 & i=$$((i+1)); done; wait
	@test "$$(find build/images -name '*.png' | wc -l | tr -d ' ')" = 5000

kindle-data:
	$(PYTHON) tools/build_kindle_data.py

test:
	$(PYTHON) -m unittest discover -s tests -v

serve:
	$(PYTHON) -m http.server 8765

package:
	$(PYTHON) tools/package_kindle.py

install:
	./tools/install_kindle.sh

release:
	./tools/release.sh $(VERSION)

clean:
	rm -rf build dist
