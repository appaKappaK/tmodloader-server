.PHONY: setup steamcmd-local engine-github tui-build tui-run install-man help

DIRS := Engine Mods Logs Worlds ModConfigs \
        Backups/Worlds Backups/Configs Backups/Full \
        Tools/SteamCMD

MANDIR ?= /usr/local/share/man/man1

help:
	@echo "tModLoader Server - Setup"
	@echo ""
	@echo "  make setup        Create required directories, copy example configs, chmod scripts"
	@echo "  make steamcmd-local Download SteamCMD into Tools/SteamCMD"
	@echo "  make engine-github Install latest tModLoader release into Engine from GitHub"
	@echo "  make tui-build    Build the persistent Go TUI into bin/tmodloader-ui"
	@echo "  make tui-run      Run the persistent Go TUI from source"
	@echo "  make install-man  Install man page to $(MANDIR) (requires sudo)"
	@echo "  make help         Show this message"

setup:
	@echo "Creating directories..."
	@mkdir -p $(DIRS)

	@echo "Copying example configs..."
	@if [ ! -f Configs/serverconfig.txt ]; then \
		cp Configs/serverconfig.example.txt Configs/serverconfig.txt; \
		echo "  Created Configs/serverconfig.txt"; \
	else \
		echo "  Configs/serverconfig.txt already exists, skipping"; \
	fi

	@if [ ! -f Scripts/steam/mod_ids.txt ]; then \
		cp Scripts/steam/mod_ids.example.txt Scripts/steam/mod_ids.txt; \
		echo "  Created Scripts/steam/mod_ids.txt"; \
	else \
		echo "  Scripts/steam/mod_ids.txt already exists, skipping"; \
	fi

	@if [ ! -f Scripts/env.sh ]; then \
		cp Scripts/env.example.sh Scripts/env.sh; \
		echo "  Created Scripts/env.sh from example (optional local overrides)"; \
	else \
		echo "  Scripts/env.sh already exists, skipping"; \
	fi

	@echo "Setting script permissions..."
	@chmod +x Scripts/**/*.sh Scripts/hub/tmod-control.sh 2>/dev/null || \
		find Scripts -name "*.sh" -exec chmod +x {} +

	@echo ""
	@echo "Setup complete. Next steps:"
	@echo "  1. Run: make steamcmd-local      # optional, installs SteamCMD into this project"
	@echo "  2. Edit Scripts/env.sh if you want local env vars like STEAM_USERNAME"
	@echo "  3. Edit Configs/serverconfig.txt only if you want non-default server settings"
	@echo "  4. Run: make tui-run             # persistent headless UI"
	@echo "     or: bash Scripts/hub/tmod-control.sh  # same control room via shell entrypoint"

steamcmd-local:
	@echo "Installing SteamCMD into Tools/SteamCMD..."
	@mkdir -p Tools/SteamCMD
	@curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
		| tar -xzf - -C Tools/SteamCMD
	@chmod +x Tools/SteamCMD/steamcmd.sh 2>/dev/null || true
	@echo "SteamCMD installed at Tools/SteamCMD/steamcmd.sh"

engine-github:
	@echo "Downloading latest tModLoader release into Engine..."
	@mkdir -p Engine
	@tmp_zip=$$(mktemp); \
		if ! curl -fsSL "https://github.com/tModLoader/tModLoader/releases/latest/download/tModLoader.zip" -o "$$tmp_zip"; then \
			rm -f "$$tmp_zip"; \
			echo "Failed to download tModLoader.zip from GitHub releases"; \
			exit 1; \
		fi; \
		if ! unzip -oq "$$tmp_zip" -d Engine; then \
			rm -f "$$tmp_zip"; \
			echo "Failed to extract tModLoader.zip into Engine"; \
			exit 1; \
		fi; \
		rm -f "$$tmp_zip"
	@if [ -f Engine/tModLoader.runtimeconfig.json ] && [ -f Engine/start-tModLoaderServer.sh ]; then \
		echo "tModLoader release extracted into Engine"; \
	else \
		echo "Engine install is missing expected tModLoader files"; \
		exit 1; \
	fi

tui-build:
	@mkdir -p bin
	@go build -o bin/tmodloader-ui .
	@echo "Built bin/tmodloader-ui"

tui-run:
	@go run .

install-man:
	@echo "Installing man page to $(MANDIR)..."
	@mkdir -p $(MANDIR)
	@gzip -c man/tmod-control.1 > /tmp/tmod-control.1.gz
	@install -m 0644 /tmp/tmod-control.1.gz $(MANDIR)/tmod-control.1.gz
	@rm /tmp/tmod-control.1.gz
	@mandb -q 2>/dev/null || true
	@echo "Done. Try: man tmod-control"
