# pwt Makefile
# Local installation and development helpers

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/pwt
COMPLETIONS_DIR ?= $(PREFIX)/share/zsh/site-functions
SHARE_DIR ?= $(PREFIX)/share/pwt

.PHONY: install uninstall test lint clean help

help:
	@echo "pwt - Power Worktrees"
	@echo ""
	@echo "Usage:"
	@echo "  make install        Install to $(PREFIX)"
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
	@mkdir -p $(COMPLETIONS_DIR)
	@mkdir -p $(SHARE_DIR)/plugins
	@install -m 755 bin/pwt $(BINDIR)/pwt
	@install -m 644 lib/pwt/*.sh $(LIBDIR)/
	@install -m 644 completions/_pwt $(COMPLETIONS_DIR)/_pwt
	@if [ -d plugins ]; then cp -r plugins/* $(SHARE_DIR)/plugins/ 2>/dev/null || true; fi
	@echo ""
	@echo "Installed successfully!"
	@echo ""
	@echo "Add to your ~/.zshrc:"
	@echo "  export PATH=\"$(BINDIR):\$$PATH\""
	@echo "  fpath=($(COMPLETIONS_DIR) \$$fpath)"
	@echo "  autoload -Uz compinit && compinit"

uninstall:
	@echo "Uninstalling pwt from $(PREFIX)..."
	@rm -f $(BINDIR)/pwt
	@rm -rf $(LIBDIR)
	@rm -f $(COMPLETIONS_DIR)/_pwt
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
	@echo "All files OK"

clean:
	@rm -rf /tmp/pwt-*
	@echo "Cleaned temporary files"
