# Terraform module for Nushell
# Provides functions for working with Terraform Cloud API

def get_api_token [] {
  open ~/.terraform.d/credentials.tfrc.json | get credentials | get "app.terraform.io" | get token
}

# Configuration for Terraform Cloud API
def get_tf_cloud_config [] {
  let api_token = get_api_token
  {
    # Base URL for Terraform Cloud API
    base_url: "https://app.terraform.io/api/v2"

    # Get API token from environment variable
    # Set this in your environment: export TF_API_TOKEN="your-token"
    api_token: $api_token,

    # Headers for API requests
    headers: {
      Authorization: ("Bearer " + $api_token),
      "Content-Type": "application/vnd.api+json"
    }
  }
}

def get_current_organization [] {
  # Get the current organization from terraform config or prompt user
  # This could be enhanced to read from terraform config files

  let config = get_tf_cloud_config

  # Try to get organizations
  try {
    let response = http get --headers ($config.headers) ($config.base_url + "/organizations")
    let orgs = $response | from json | get data

    if ($orgs | is-empty) {
      print "No organizations found or unable to fetch organizations"
      return null
    }

    # For now, return the first organization
    # This could be enhanced to let user select or read from config
    return ($orgs | first | get attributes | get name)
  } catch { |error|
    print "Error fetching organizations: " + $error
    return null
  }
}

export def "variables" [--workspace: string] {
  # Get terraform variables from Terraform Cloud API for the current workspace
  # If --workspace is provided, use that workspace, otherwise try to get current workspace

  let config = get_tf_cloud_config

  if ($config.api_token | is-empty) {
    print "Error: TF_API_TOKEN environment variable not set"
    print "Please set your Terraform Cloud API token: export TF_API_TOKEN='your-token'"
    return
  }

  # Get organization
  let org = get_current_organization

  if ($org | is-empty) {
    print "Could not determine organization"
    return
  }

  # Determine workspace
  mut workspace_name = $workspace

  if ($workspace_name | is-empty) {
    # Try to get current workspace from terraform config
    # This is a placeholder - could be enhanced to read from .terraform/terraform.tfstate
    try {
      let workspace_response = http get --headers ($config.headers) ($config.base_url + "/organizations/" + $org + "/workspaces")
      let workspaces = $workspace_response | from json | get data

      if ($workspaces | is-empty) {
        print "No workspaces found in organization: $org"
        return
      }

      # For now, use the first workspace
      # This could be enhanced to detect current workspace
      $workspace_name = ($workspaces | first | get attributes | get name)
      print "Using first workspace found: $workspace_name"
    } catch { |error|
      print "Error fetching workspaces: " + $error
      return
    }
  }

  # Get workspace ID
  mut workspace_id = ""
  try {
    let workspace_response = http get --headers ($config.headers) ($config.base_url + "/organizations/" + $org + "/workspaces/" + $workspace_name)
    let workspace_data = $workspace_response | from json | get data
    $workspace_id = ($workspace_data | get id)
  } catch { |error|
    print "Error getting workspace ID: " + $error
    return
  }

  # Get variables for the workspace
  try {
    let variables_response = http get --headers ($config.headers) ($config.base_url + "/workspaces/" + $workspace_id + "/vars")
    let variables_data = $variables_response | from json | get data

    if ($variables_data | is-empty) {
      print "No variables found in workspace: $workspace_name"
      return
    }

    # Process and display variables
    $variables_data | each { |var|
      let attributes = $var.attributes
      {
        "id": $var.id,
        "key": $attributes.key,
        "value": $attributes.value,
        "category": $attributes.category,
        "hcl": $attributes.hcl,
        "sensitive": $attributes.sensitive
      }
    }
  } catch { |error|
    print "Error fetching variables: " + $error
    return
  }
}

export def "workspaces" [--org: string] {
  # List available workspaces in Terraform Cloud

  let config = get_tf_cloud_config

  let organization = $org | default (get_current_organization)

  if ($organization | is-empty) {
    print "Could not determine organization"
    return
  }

  try {
    let response = http get --headers ($config.headers) ($config.base_url + "/organizations/" + $organization + "/workspaces")
    let workspaces = $response | from json | get data

    if ($workspaces | is-empty) {
      print "No workspaces found in organization: $organization"
      return
    }

    $workspaces | each { |ws|
      let attributes = $ws.attributes
      {
        "id": $ws.id,
        "name": $attributes.name,
        "description": $attributes.description,
        "working-directory": $attributes."working-directory",
        "terraform-version": $attributes."terraform-version"
      }
    }
  } catch { |error|
    print "Error fetching workspaces: " + $error
  }
}

export def "organizations" [] {
  # List available organizations in Terraform Cloud

  let config = get_tf_cloud_config

  try {
    let response = http get --headers ($config.headers) ($config.base_url + "/organizations")
    let orgs = $response | from json | get data

    if ($orgs | is-empty) {
      print "No organizations found"
      return
    }

    $orgs | each { |org|
      let attributes = $org.attributes
      {
        "id": $org.id,
        "name": $attributes.name,
        "email": $attributes.email,
        "created-at": $attributes."created-at"
      }
    }
  } catch { |error|
    print "Error fetching organizations: " + $error
  }
}

export def "set-variable" [key: string, value: string, --workspace: string, --category: string = "terraform", --hcl = false, --sensitive = false] {
  # Set a variable in Terraform Cloud

  let config = get_tf_cloud_config

  let organization = get_current_organization

  if ($organization | is-empty) {
    print "Could not determine organization"
    return
  }

  # Get workspace ID
  mut workspace_id = ""
  try {
    let workspace_response = http get --headers ($config.headers) ($config.base_url + "/organizations/" + $organization + "/workspaces/" + $workspace)
    let workspace_data = $workspace_response | from json | get data
    $workspace_id = ($workspace_data | get id)
  } catch { |error|
    print "Error getting workspace ID: " + $error
    return
  }

  # Create variable payload
  let payload = {
    "data": {
      "type": "vars",
      "attributes": {
        "key": $key,
        "value": $value,
        "category": $category,
        "hcl": $hcl,
        "sensitive": $sensitive
      }
    }
  }

  try {
    let response = http post --headers ($config.headers) --content-type application/json ($config.base_url + "/workspaces/" + $workspace_id + "/vars") $payload
    print "Variable set successfully"
    $response | from json | get data
  } catch { |error|
    print "Error setting variable: " + $error
  }
}

export def "del-variable" [key: string, --workspace: string, --all = false, --force = false] {

  # Delete a variable from Terraform Cloud
  # If --all is true, delete all variables matching the key pattern
  # If --force is true, skip confirmation prompt

  let config = get_tf_cloud_config

  if ($config.api_token | is-empty) {
    echo "Error: TF_API_TOKEN environment variable not set"
    return
  }

  let organization = get_current_organization

  if ($organization | is-empty) {
    echo "Could not determine organization"
    return
  }

  # Get workspace ID
  mut workspace_id = ""
  try {
    let workspace_response = http get --headers ($config.headers) ($config.base_url + "/organizations/" + $organization + "/workspaces/" + $workspace)
    let workspace_data = $workspace_response | from json | get data
    $workspace_id = ($workspace_data | get id)
  } catch { |error|
    echo "Error getting workspace ID: " + $error
    return
  }

  # Get all variables to find the one(s) to delete
  mut variables_to_delete = []
  try {
    let variables_response = http get --headers ($config.headers) ($config.base_url + "/workspaces/" + $workspace_id + "/vars")
    let variables_data = $variables_response | from json | get data

    if ($variables_data | is-empty) {
      echo "No variables found in workspace: $workspace"
      return
    }

    if ($all) {
      # Delete all variables matching the key pattern
      $variables_to_delete = ($variables_data | where { |var| $var.attributes.key =~ $key })
    } else {
      # Delete exact match
      $variables_to_delete = ($variables_data | where { |var| $var.attributes.key == $key })
    }

    if (($variables_to_delete | length) == 0) {
      echo "No variables found matching: $key"
      return
    }
  } catch { |error|
    echo "Error fetching variables: " + $error
    return
  }

  # Show what will be deleted and ask for confirmation
  if (($force) != true) {
    echo ""
    echo "WARNING: You are about to delete the following variables from workspace '$workspace':"
    echo "---"

    $variables_to_delete | each { |var|
      let var_key = $var.attributes.key
      let var_value = $var.attributes.value
      let var_category = $var.attributes.category
      let var_sensitive = $var.attributes.sensitive

      echo "Key: $var_key"
      echo "Category: $var_category"
      if ($var_sensitive) {
        echo "Value: [SENSITIVE - HIDDEN]"
      } else {
        echo "Value: $var_value"
      }
      echo "ID: $var.id"
      echo "---"
    }

    echo ""
    let confirm = (input "Are you sure you want to delete these variables? (y/N): ")

    if ($confirm | str downcase) != "y" {
      echo "Deletion cancelled."
      return
    }
  }

  # Delete each variable
  echo ""
  echo "Deleting variables..."

  $variables_to_delete | each { |var|
    let var_id = $var.id
    let var_key = $var.attributes.key

    try {
      let response = http delete --headers ($config.headers) ($config.base_url + "/vars/" + $var_id)
      echo "✓ Deleted variable: $var_key (ID: $var_id)"
    } catch { |error|
      echo "✗ Error deleting variable $var_key: " + $error
    }
  }

  echo ""
  echo "Variable deletion complete."
}

