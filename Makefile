# pwt Makefile
# Local installation and development helpers

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/pwt
MANDIR ?= $(PREFIX)/share/man/man1
SHARE_DIR ?= $(PREFIX)/share/pwt
ZSH_COMPLETIONS ?= $(PREFIX)/share/zsh/site-functions
BASH_COMPLETIONS ?= $(PREFIX)/share/bash-completion/completions
FISH_COMPLETIONS ?= $(PREFIX)/share/fish/vendor_completions.d

.PHONY: install uninstall update test lint clean help

help:
	@echo "pwt - Power Worktrees"
	@echo ""
	@echo "Usage:"
	@echo "  make install        Install to $(PREFIX)"
	@echo "  make update         Update existing installation (auto-detects PREFIX)"
	@echo "  make uninstall      Remove from $(PREFIX)"
	@echo "  make test           Run tests"
	@echo "  make lint           Check bash syntax"
	@echo "  make clean          Clean temporary files"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX=$(PREFIX)"
	@echo "  BINDIR=$(BINDIR)"
	@echo ""
	@echo "Examples:"
	@echo "  make install                    # Install to /usr/local"
	@echo "  make install PREFIX=~/.local   # Install to ~/.local"
	@echo "  sudo make install               # System-wide install"

install:
	@echo "Installing pwt to $(PREFIX)..."
	@mkdir -p $(BINDIR)
	@mkdir -p $(LIBDIR)
	@mkdir -p $(MANDIR)
	@mkdir -p $(ZSH_COMPLETIONS)
	@mkdir -p $(BASH_COMPLETIONS)
	@mkdir -p $(FISH_COMPLETIONS)
	@mkdir -p $(SHARE_DIR)/plugins
	@# Main script
	@install -m 755 bin/pwt $(BINDIR)/pwt
	@echo "  ✓ Installed bin/pwt"
	@# Library modules
	@install -m 644 lib/pwt/*.sh $(LIBDIR)/
	@echo "  ✓ Installed lib/pwt modules"
	@# Man page
	@install -m 644 man/pwt.1 $(MANDIR)/pwt.1
	@echo "  ✓ Installed man page"
	@# Completions
	@install -m 644 completions/_pwt $(ZSH_COMPLETIONS)/_pwt
	@echo "  ✓ Installed zsh completions"
	@install -m 644 completions/pwt.bash $(BASH_COMPLETIONS)/pwt
	@echo "  ✓ Installed bash completions"
	@install -m 644 completions/pwt.fish $(FISH_COMPLETIONS)/pwt.fish
	@echo "  ✓ Installed fish completions"
	@# Plugins (optional)
	@if [ -d plugins ]; then cp -r plugins/* $(SHARE_DIR)/plugins/ 2>/dev/null || true; fi
	@echo ""
	@echo "Installed successfully!"
	@echo ""
	@echo "Shell setup:"
	@echo ""
	@echo "  Zsh (~/.zshrc):"
	@echo "    export PATH=\"$(BINDIR):\$$PATH\""
	@echo "    fpath=($(ZSH_COMPLETIONS) \$$fpath)"
	@echo "    autoload -Uz compinit && compinit"
	@echo ""
	@echo "  Bash (~/.bashrc):"
	@echo "    export PATH=\"$(BINDIR):\$$PATH\""
	@echo "    source $(BASH_COMPLETIONS)/pwt"
	@echo ""
	@echo "  Fish (~/.config/fish/config.fish):"
	@echo "    fish_add_path $(BINDIR)"
	@echo ""
	@echo "View manual: man pwt"

# Update existing installation (auto-detects PREFIX)
update:
	@pwt_path=$$(command -v pwt 2>/dev/null | head -1); \
	if [ -z "$$pwt_path" ]; then \
		echo "Error: pwt not found in PATH. Use 'make install' instead."; \
		exit 1; \
	fi; \
	if [ "$$(type -t pwt 2>/dev/null)" = "function" ]; then \
		pwt_path=$$(type pwt | grep -o '"/[^"]*"' | head -1 | tr -d '"'); \
	fi; \
	if [ -z "$$pwt_path" ] || [ ! -f "$$pwt_path" ]; then \
		echo "Error: Could not determine pwt binary path"; \
		exit 1; \
	fi; \
	prefix=$$(dirname $$(dirname $$pwt_path)); \
	echo "Detected installation at: $$prefix"; \
	echo "Updating..."; \
	install -m 755 bin/pwt $$prefix/bin/pwt; \
	echo "  ✓ Updated bin/pwt"; \
	mkdir -p $$prefix/lib/pwt; \
	install -m 644 lib/pwt/*.sh $$prefix/lib/pwt/; \
	echo "  ✓ Updated lib/pwt modules"; \
	if [ -d $$prefix/share/zsh/site-functions ]; then \
		install -m 644 completions/_pwt $$prefix/share/zsh/site-functions/_pwt; \
		echo "  ✓ Updated zsh completions"; \
	fi; \
	echo ""; \
	echo "Updated successfully!"

uninstall:
	@echo "Uninstalling pwt from $(PREFIX)..."
	@rm -f $(BINDIR)/pwt
	@rm -rf $(LIBDIR)
	@rm -f $(MANDIR)/pwt.1
	@rm -f $(ZSH_COMPLETIONS)/_pwt
	@rm -f $(BASH_COMPLETIONS)/pwt
	@rm -f $(FISH_COMPLETIONS)/pwt.fish
	@rm -rf $(SHARE_DIR)
	@echo "Uninstalled successfully!"

test:
	@if command -v bats >/dev/null; then \
		bats tests/; \
	else \
		echo "bats not installed. Install with: brew install bats-core"; \
		exit 1; \
	fi

lint:
	@echo "Checking bash syntax..."
	@bash -n bin/pwt
	@for f in lib/pwt/*.sh; do bash -n "$$f" && echo "  ✓ $$f"; done
	@bash -n completions/pwt.bash && echo "  ✓ completions/pwt.bash"
	@echo "All files OK"

clean:
	@rm -rf /tmp/pwt-*
	@echo "Cleaned temporary files"
