.PHONY: help setup install-orbstack provision passthrough install-skill doctor shell run reset uninstall clean lint test

# Default VM config (overridable on the command line, e.g. `make setup VM=m2`).
VM        ?= atelier
CPUS      ?= 4
MEMORY    ?= 8G
DISK      ?= 64G
DISTRO    ?= ubuntu:24.04
CN_MIRROR ?= 1

help: ## show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf "\nEnv vars (override with: make setup VM=foo CPUS=8 ...):\n"
	@printf "  VM         target machine name (default: $(VM))\n"
	@printf "  CPUS       VM CPUs (default: $(CPUS))\n"
	@printf "  MEMORY     VM RAM (default: $(MEMORY))\n"
	@printf "  DISK       VM disk (default: $(DISK))\n"
	@printf "  DISTRO     OrbStack distro string (default: $(DISTRO))\n"
	@printf "  CN_MIRROR  1 = mainland-China mirrors, 0 = international (default: $(CN_MIRROR))\n\n"

# --- one-time setup ---------------------------------------------------------
install-orbstack: ## install OrbStack via brew (or download .dmg as fallback)
	@./setup/install-orbstack.sh

setup: install-orbstack provision passthrough install-skill doctor ## full first-time setup
	@printf "\n\033[1;32m✓ atelier ready.\033[0m try: make shell\n"

provision: ## run the in-VM provision script (idempotent)
	@DEVBOX_VM=$(VM) DEVBOX_CPUS=$(CPUS) DEVBOX_MEMORY=$(MEMORY) \
	 DEVBOX_DISK=$(DISK) DEVBOX_DISTRO=$(DISTRO) CN_MIRROR=$(CN_MIRROR) \
	 ./bin/devbox provision

passthrough: ## mirror host env (ANTHROPIC_*, GITHUB_TOKEN) into the VM
	@./setup/host-passthrough.sh

install-skill: ## symlink plugin/skills/atelier into ~/.claude/skills/
	@SKILL_SRC="$$(pwd)/plugin/skills/atelier"; \
	 SKILL_DST="$${HOME}/.claude/skills/atelier"; \
	 mkdir -p "$${HOME}/.claude/skills"; \
	 if [[ -L "$$SKILL_DST" ]]; then rm -f "$$SKILL_DST"; \
	 elif [[ -e "$$SKILL_DST" ]]; then \
	   printf "\033[1;33m!\033[0m $$SKILL_DST exists and is not a symlink — leaving it alone\n" >&2; \
	   exit 1; \
	 fi; \
	 ln -s "$$SKILL_SRC" "$$SKILL_DST"; \
	 printf "   linked $$SKILL_DST -> $$SKILL_SRC\n"

doctor: ## check that OrbStack, the VM, mounts, and env passthrough are all green
	@./bin/devbox doctor

# --- daily use --------------------------------------------------------------
shell: ## open an interactive shell in the VM
	@./bin/devbox shell

run: ## run a command inside the VM (e.g. `make run CMD='pnpm test'`)
	@./bin/devbox run $(CMD)

reset: ## destroy + recreate the VM from scratch (DESTRUCTIVE)
	@./bin/devbox reset

# --- maintenance ------------------------------------------------------------
uninstall: ## remove the VM and (optionally) OrbStack itself
	@./setup/uninstall.sh

clean: ## remove generated artifacts (.DS_Store, local caches) — safe
	@find . -name '.DS_Store' -delete 2>/dev/null || true
	@rm -rf .cache .tmp 2>/dev/null || true
	@printf "cleaned.\n"

lint: ## best-effort shellcheck (skips if shellcheck is not installed)
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not installed; skipping"; exit 0; }
	@shellcheck bin/devbox setup/*.sh

test: ## run the provision script in a fresh VM to verify it from zero
	@echo "test target: invokes 'make reset' which is destructive; press Ctrl-C now if unsure"
	@read -p "type 'yes' to continue: " c && [ "$$c" = "yes" ]
	@$(MAKE) reset
	@$(MAKE) doctor
