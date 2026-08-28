# ╔══════════════════════════════════════════════════════════════════╗
# ║  Makefile                                                          ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  Terraform + contract-test tasks. terraform is optional: the     ║
# ║  offline lane (make test) runs with python only.                  ║
# ╚══════════════════════════════════════════════════════════════════╝

SHELL            := /bin/bash
PYTHON           ?= python3
VENV             ?= .venv-tf
TERRAFORM        ?= terraform
ENV              ?= dev          # which examples/*/environments/<env>.tfvars to use
MODULES          := $(notdir $(wildcard modules/*))
EXAMPLES         := $(notdir $(wildcard examples/*))
HAVE_TF          := $(shell command -v $(TERRAFORM) >/dev/null 2>&1 && echo 1 || echo 0)
HAVE_TFLINT      := $(shell command -v tflint >/dev/null 2>&1 && echo 1 || echo 0)
PYTEST           := $(PYTHON) -m pytest

.DEFAULT_GOAL := help
.PHONY: help venv fmt fmt-check validate test test-terraform lint docs docs-check \
        plan apply destroy clean ci $(addprefix plan-,$(EXAMPLES)) $(addprefix validate-,$(MODULES))

help: ## Show this help
	@grep -hE '^[a-zA-Z_0-9-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  modules:  $(MODULES)"
	@echo "  examples: $(EXAMPLES)"
	@echo "  terraform found: $(HAVE_TF)   tflint found: $(HAVE_TFLINT)"

venv: ## Create ./.venv-tf with the test dependencies
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip >/dev/null
	$(VENV)/bin/pip install -r tests/requirements.txt

fmt: ## terraform fmt -recursive (skipped when terraform is unavailable)
ifeq ($(HAVE_TF),1)
	$(TERRAFORM) fmt -recursive -write=true .
else
	@echo "terraform not installed - skipping fmt"
endif

fmt-check: ## Fail if terraform fmt would change anything
ifeq ($(HAVE_TF),1)
	@$(TERRAFORM) fmt -recursive -check -diff . && echo "fmt: clean"
else
	@echo "terraform not installed - fmt-check skipped (the offline lane still checks style)"
endif

test: ## Run the offline contract suite (no cloud credentials, no terraform)
	$(PYTEST) tests -c tests/pytest.ini

test-verbose: ## Contract suite with per-test output
	$(PYTEST) tests -c tests/pytest.ini -v -ra

test-terraform: ## Run `terraform test` for every module (needs terraform >= 1.6)
ifeq ($(HAVE_TF),1)
	@set -e; for module in $(MODULES); do \
		echo ":: module $$module"; \
		cd modules/$$module; \
		$(TERRAFORM) init -input=false -backend=false >/dev/null; \
		$(TERRAFORM) test || { cd ../..; exit 1; }; \
		cd ../..; \
	done
	@echo "terraform test: all modules passed"
else
	@echo "terraform not installed - run the suite in CI (.github/workflows/terraform.yml)"
endif

validate: ## terraform init + validate for modules and examples
ifeq ($(HAVE_TF),1)
	@set -e; for dir in $(addprefix modules/,$(MODULES)) $(addprefix examples/,$(EXAMPLES)); do \
		echo ":: $$dir"; \
		(cd $$dir && $(TERRAFORM) init -input=false -backend=false >/dev/null && $(TERRAFORM) validate); \
	done
else
	@echo "terraform not installed - 'make test' covers structure, schema and wiring"
endif

lint: fmt-check docs-check ## fmt check + README drift + tflint (when installed)
ifeq ($(HAVE_TFLINT),1)
	@set -e; for module in $(MODULES); do \
		echo ":: tflint modules/$$module"; \
		(cd modules/$$module && tflint --chdir=. --recursive=false); \
	done
else
	@echo "tflint not installed - skipping (CI runs it)"
endif

docs: ## Regenerate the Inputs/Outputs tables inside every README
	$(PYTHON) tools/gen-docs.py

docs-check: ## Fail if a README table is out of date
	$(PYTHON) tools/gen-docs.py --check

validate-%: ## terraform init + validate for one module, e.g. `make validate-acr`
	cd modules/$* && $(TERRAFORM) init -input=false -backend=false && $(TERRAFORM) validate

plan-%: ## terraform plan for one example, e.g. `make plan-full-stack ENV=prod`
	@test -f examples/$*/environments/$(ENV).tfvars || { echo "examples/$*/environments/$(ENV).tfvars missing"; exit 2; }
	cd examples/$* && $(TERRAFORM) init -input=false && $(TERRAFORM) plan -var-file=environments/$(ENV).tfvars

apply-%: ## terraform apply for one example (ENV=dev|prod)
	cd examples/$* && $(TERRAFORM) apply -var-file=environments/$(ENV).tfvars

destroy-%: ## terraform destroy for one example (ENV=dev|prod)
	cd examples/$* && $(TERRAFORM) destroy -var-file=environments/$(ENV).tfvars

ci: fmt-check docs-check test ## Everything the pull request gate runs
ifeq ($(HAVE_TF),1)
	$(MAKE) validate
	$(MAKE) test-terraform
endif

clean: ## Remove local state and provider caches created by the examples
	rm -rf examples/*/.terraform examples/*/.terraform.lock.hcl examples/*/terraform.tfstate*
	rm -rf modules/*/.terraform modules/*/.terraform.lock.hcl
	find . -name '__pycache__' -type d -prune -exec rm -rf {} +
