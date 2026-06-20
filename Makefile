BINARY = dms-ai-usage
PREFIX = $(HOME)/.local
PLUGIN_DIR = $(HOME)/.config/DankMaterialShell/plugins

build:
	go build -o $(BINARY) .

install: build
	install -m 0755 $(BINARY) $(PREFIX)/bin/$(BINARY)

install-plugin:
	mkdir -p $(PLUGIN_DIR)
	ln -sfn $(CURDIR)/plugin $(PLUGIN_DIR)/AiUsage

install-all: install install-plugin

uninstall:
	rm -f $(PREFIX)/bin/$(BINARY)
	rm -f $(PLUGIN_DIR)/AiUsage

clean:
	rm -f $(BINARY)

.PHONY: build install install-plugin install-all uninstall clean
