# tflint configuration for modules/ and examples/.
#
#   tflint --init                 # once, downloads the plugins below
#   tflint --chdir=modules/acr    # per directory (what CI runs)
#
# The terraform_* rules are language level and work offline; the azurerm_* rules
# need the plugin and catch provider-specific mistakes the schema check in
# tests/ does not (value shapes, not argument names).
plugin "terraform" {
  enabled = true
  version = "0.6.0"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.29.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# ─── Documented, typed and reproducible inputs ─────────────────────
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true

  # Only the identifier shapes tflint's terraform ruleset actually documents;
  # snake_case everywhere keeps `terraform state` addresses predictable.
  rule {
    variable = {
      format = "snake_case"
    }
    output = {
      format = "snake_case"
    }
    resource = {
      format = "snake_case"
    }
    data = {
      format = "snake_case"
    }
    module = {
      format = "snake_case"
    }
  }
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

# Deliberately NOT enabled:
#   terraform_required_version / terraform_required_providers - modules pin both
#     in versions.tf, and examples must stay free to omit a version block when
#     the CI matrix pins the binary.
#   terraform_workspace_remote - examples document local state for evaluation;
#     the README tells teams to switch to the remote backend before applying.
rule "terraform_workspace_remote" {
  enabled = false
}
