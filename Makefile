SHELL := /bin/bash
PREFIX ?= $(HOME)/.local
LIBDIR := $(PREFIX)/lib/porthole
BINDIR := $(PREFIX)/bin
DATADIR := $(HOME)/.local/share
VERSION := $(shell cat VERSION)

SRC := bin libexec config windows tools assets docs

.PHONY: all check encoding syntax test install uninstall desktop clean

all: check

encoding:
	./tools/check-encoding.sh

syntax:
	@for f in bin/porthole libexec/porthole libexec/lib/*.sh tools/check-encoding.sh; do \
		bash -n "$$f" || exit 1; \
	done
	@python3 -m py_compile tools/toml2env.py tools/fetch-iso.py
	@echo "syntax ok"

check: encoding syntax
	@echo "check ok"

test: check
	@./bin/porthole --version
	@./bin/porthole config show >/dev/null
	@./bin/porthole -p notepad config show >/dev/null
	@echo "test ok"

install: check
	install -d "$(LIBDIR)" "$(BINDIR)"
	rm -rf $(addprefix "$(LIBDIR)/",$(SRC))
	cp -a $(SRC) VERSION README.md LICENSE "$(LIBDIR)/"
	printf '#!/bin/sh\nexec "%s/bin/porthole" "$$@"\n' "$(LIBDIR)" >"$(BINDIR)/porthole"
	chmod 755 "$(BINDIR)/porthole"
	$(MAKE) --no-print-directory desktop
	@echo "installed porthole $(VERSION) -> $(BINDIR)/porthole"

desktop:
	install -d "$(DATADIR)/applications" "$(DATADIR)/icons/hicolor/256x256/apps"
	sed -e 's|@EXEC@|$(BINDIR)/porthole run wecom|' \
	    -e 's|@ICON@|wecom|' \
	    assets/porthole-wecom.desktop.in >"$(DATADIR)/applications/porthole-wecom.desktop"
	cp -f assets/icons/wecom.png "$(DATADIR)/icons/hicolor/256x256/apps/wecom.png"
	-update-desktop-database "$(DATADIR)/applications" >/dev/null 2>&1 || true
	-gtk-update-icon-cache -f -t "$(DATADIR)/icons/hicolor" >/dev/null 2>&1 || true
	@echo "desktop entry installed"

uninstall:
	rm -rf "$(LIBDIR)"
	rm -f "$(BINDIR)/porthole" "$(DATADIR)/applications/porthole-wecom.desktop"
	rm -f "$(DATADIR)/icons/hicolor/256x256/apps/wecom.png"
	@echo "removed the porthole code; VM data stays under ~/.local/share/porthole"

clean:
	rm -rf tools/__pycache__
