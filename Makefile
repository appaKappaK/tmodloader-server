.PHONY: setup steamcmd-local install-man help

DIRS := Engine Mods Logs Worlds ModConfigs \
        Backups/Worlds Backups/Configs Backups/Full \
        Tools/SteamCMD

MANDIR ?= /usr/local/share/man/man1

help:
	@echo "tModLoader Server - Setup"
	@echo ""
	@echo "  make setup        Create required directories, copy example configs, chmod scripts"
	@echo "  make steamcmd-local Download SteamCMD into Tools/SteamCMD"
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
	@echo "  4. Run: bash Scripts/hub/tmod-control.sh"

steamcmd-local:
	@echo "Installing SteamCMD into Tools/SteamCMD..."
	@mkdir -p Tools/SteamCMD
	@curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
		| tar -xzf - -C Tools/SteamCMD
	@chmod +x Tools/SteamCMD/steamcmd.sh 2>/dev/null || true
	@echo "SteamCMD installed at Tools/SteamCMD/steamcmd.sh"

install-man:
	@echo "Installing man page to $(MANDIR)..."
	@mkdir -p $(MANDIR)
	@gzip -c man/tmod-control.1 > /tmp/tmod-control.1.gz
	@install -m 0644 /tmp/tmod-control.1.gz $(MANDIR)/tmod-control.1.gz
	@rm /tmp/tmod-control.1.gz
	@mandb -q 2>/dev/null || true
	@echo "Done. Try: man tmod-control"
