locals {
  azu_build_name            = "azu-build"
  namespaced_azu_build_name = "${local.namespace-}azu-build"
  deploy_azu_build          = merge(azurerm_linux_function_app.azu_build.app_settings, { "src_artifact" : data.archive_file.azu_build_src.output_md5, "principal_id" : azurerm_linux_function_app.azu_build.identity[0].principal_id })
  codebuild_image_name      = "BaseImage"
  build_resource_group_location   = local.is_local ? data.azurerm_resource_group.build_network[0].location : azurerm_resource_group.build_network[0].location
  build_resource_group_name       = local.is_local ? data.azurerm_resource_group.build_network[0].name : azurerm_resource_group.build_network[0].name
  infra_name                      = "${local.namespace}_golden_image_azu_build"
  subscription_with_underscores   = replace(data.azurerm_subscription.current.subscription_id, "-", "_")
  owner_group_name                = format("AZU_%s_Contributors", local.subscription_with_underscores)
}

data "archive_file" "azu_build_src" {
  type        = "zip"
  source_dir  = "${path.module}/azu-build"
  output_path = "${local.namespaced_azu_build_name}.zip"
}

# Function App Infra

resource "azurerm_storage_account" "azu_build" {
  name                            = "${local.namespace}azubuildfunc"
  resource_group_name             = "${local.build_resource_group_name}"
  location                        = "${local.build_resource_group_location}"
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
}

resource "azurerm_storage_container" "azubuild_container" {
  name                  = "${local.namespaces-}azubuild"
  storage_account_name  = azurerm_storage_account.azu_build.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "supported_images_blob" {
  name                      = "supported-images.json"
  storage_account_name      = azurerm_storage_account.azu_build.name
  storage_container_name    = azurerm_storage_container.azubuild_container.name
  content_md5               = filemd5("${path.module}/../../supported_images.json")
  type                      = "Block"
  source                    = "${path.module}/../../supported_images.json"

}

resource "azurerm_storage_blob" "exceptional_images_blob" {
  name                      = "exceptional-images.json"
  storage_account_name      = azurerm_storage_account.azu_build.name
  storage_container_name    = azurerm_storage_container.azubuild_container.name
  content_md5               = filemd5("${path.module}/../../exceptional-images.json")
  type                      = "Block"
  source                    = "${path.module}/../../exceptional-images.json"

}

resource "azurerm_storage_blob" "exceptional_images_access_blob" {
  name                      = "exceptional-images-access.json"
  storage_account_name      = azurerm_storage_account.azu_build.name
  storage_container_name    = azurerm_storage_container.azubuild_container.name
  content_md5               = filemd5("${path.module}/exceptional_images_access.json")
  type                      = "Block"
  source                    = "${path.module}/exceptional_images_access.json"

}

data "archive_file" "ansible" {
  type        = "zip"
  source_dir  = "${path.module}/../../ansible"
  output_path = "${path.module}/codebuild/ansible.zip"
}

data "archive_file" "builder" {
  type        = "zip"
  source_dir  = "${path.module}/codebuild"
  output_path = "${path.root}/codebuild.zip"

  depends_on = [
    data.archive_file.ansible
  ]
}

resource "azurerm_storage_container" "build" {
  name                  = "build"
  storage_account_name  = azurerm_storage_account.azu_build.name
  container_access_type = "private"
}

resource "null_resource" "create_blob" {
  triggers = {
    file = data.archive_file.builder.output_md5
  }
  provisioner "local-exec" {
    command = "az storage blob upload-batch --destination ${azurerm_storage_container.build.name} --source ${path.module}/codebuild --account-name ${azurerm_storage_account.azu_build.name} --account-key ${azurerm_storage_account.azu_build.primary_access_key} --overwrite"
  }
  depends_on = [
    azurerm_storage_container.build,
    data.archive_file.ansible,
    data.archive_file.builder
  ]
}
# creating Container to store the build logs inside it
resource "azurerm_storage_container" "build_logs" {
  name                  = "azu-build-logs"
  storage_account_name  = azurerm_storage_account.azu_build.name
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "build_logs_lifecycle" {
  storage_account_id = azurerm_storage_account.azu_build.id

  rule {
    name    = "delete-build-blobs"
    enabled = true
    filters {
      prefix_match = ["azu-build-logs/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = 30
      }
      snapshot {
        delete_after_days_since_creation_greater_than = 30
      }
    }
  }
}


resource "azurerm_service_plan" "azu_build" {
  name                = "${local.base_name}_azu_build"
  resource_group_name = "${local.build_resource_group_name}"
  location            = "${local.build_resource_group_location}"
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_storage_share" "azu_build" {
  name                 = "${local.namespace-}azu-build-share"
  storage_account_name = azurerm_storage_account.azu_build.name
  quota                = 100
}

resource "azurerm_linux_function_app" "azu_build" {
  name                            = local.namespaced_azu_build_name
  resource_group_name             = "${local.build_resource_group_name}"
  location                        = "${local.build_resource_group_location}"

  storage_account_name       = azurerm_storage_account.azu_build.name
  storage_account_access_key = azurerm_storage_account.azu_build.primary_access_key
  service_plan_id            = azurerm_service_plan.azu_build.id

  app_settings = {
    is_local                  = local.is_local
    is_poc                    = local.is_poc
    is_prod                   = local.is_prod
    DYNAMODB_TABLE_NAME       = data.aws_dynamodb_table.common_image_table.name
    RESOURCE_GROUP_NAME       = "${local.build_resource_group_name}"
    SUBSCRIPTION_ID           = data.azurerm_subscription.current.subscription_id
    NAMESPACE                 = "${local.namespace}"
    STORAGE_ACCOUNT_CONTAINER = azurerm_storage_container.azubuild_container.name
    STORAGE_ACCOUNT_URL       = azurerm_storage_account.azu_build.primary_blob_endpoint
    KEY_VAULT_URI             = azurerm_key_vault.build.vault_uri
    KEY_VAULT_IAM_USER_NAME   = azurerm_key_vault_secret.image_assess_iam_user_id.name
    KEY_VAULT_IAM_SECRET_NAME = azurerm_key_vault_secret.image_assess_iam_user_secret.name
    GALLERY_NAME              = "${local.gallery_name}"
    EXCEPTION_GALLERY_NAME    = local.exceptional_gallery_name
    STORAGE_ACCOUNT_NAME      = azurerm_storage_account.azu_build.name
    AZU_CLIENT_ID             = var.azu_client_id
    AZU_CLIENT_SECRET         = var.azu_client_secret
    AZU_TENANT                = var.azu_tenant
    regions                   = jsonencode(local.azu_regions_list)
    ami_api_endpoint          = data.aws_secretsmanager_secret.image_api_url.name
    managed_identity          = azurerm_user_assigned_identity.managed_identity.id
    BUILD_IMAGE_NAME          = "${local.codebuild_image_name}"
    ASK_ID                    = "AIDE_0077829"
    INFRA_NAME                = "${local.infra_name}"
    PROJECT_NAME              = "CDTK"
    EXCEPTION_STORAGE_ACCOUNT = local.exceptional_storage_account_name
    PK_VAR_storage_account    = azurerm_storage_account.gallery_backup.name
    KEY_VAULT_SSH_URI         = azurerm_key_vault.azu_build_ssh.vault_uri
    KEY_VAULT_SSH_PUBLIC      = azurerm_key_vault_secret.az_build_vm_ssh_public_key.name
    TOPIC_NAME                = data.aws_sns_topic.images_notification_topic.arn
    BACKUP_STORAGE_ACCOUNT_URL= azurerm_storage_account.gallery_backup.primary_blob_endpoint
    EXP_BACKUP_STORAGE_ACCOUNT_URL= azurerm_storage_account.exceptional_gallery_backup.primary_blob_endpoint
  }

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.build.connection_string
    application_insights_key               = azurerm_application_insights.build.instrumentation_key
    application_stack {
      python_version = 3.9
    }
    cors {
      allowed_origins     = ["https://portal.azure.com"]
      support_credentials = false
    
    }
    scm_use_main_ip_restriction = true
    ip_restriction {
      priority = "200"
      name = "Allow Subnet access"
      virtual_network_subnet_id = azurerm_subnet.build_network["${local.build_name}"].id
      action = "Allow"
    }
    ip_restriction {
      priority = "210"
      name = "Allow optum tower ip access"
      ip_address = "149.111.0.0/16"
      action = "Allow"
    }
    ip_restriction {
      priority = "220"
      name = "Allow optum tower ip access"
      ip_address = "168.183.0.0/16"
      action = "Allow"
    }
    ip_restriction {
      priority = "230"
      name = "Allow optum tower ip access"
      ip_address = "128.35.0.0/16"
      action = "Allow"
    }
    ip_restriction {
      priority = "240"
      name = "Allow optum tower ip access"
      ip_address = "161.249.0.0/16"
      action = "Allow"
    }
    ip_restriction {
      priority = "250"
      name = "Allow optum tower ip access"
      ip_address = "198.203.174.0/23"
      action = "Allow"
    }
    ip_restriction {
      priority = "260"
      name = "Allow optum tower ip access"
      ip_address = "198.203.176.0/22"
      action = "Allow"
    }
    ip_restriction {
      priority = "270"
      name = "Allow optum tower ip access"
      ip_address = "198.203.180.0/23"
      action = "Allow"
    }
    ip_restriction {
      priority = "280"
      name = "allow test and code UI access"
      service_tag = "AzureCloud"
      action = "Allow"
    }
    ip_restriction {
      priority = "310"
      name = "Allow github runner ips"
      ip_address = "20.120.134.64/29"
      action = "Allow"
    }
    ip_restriction {
      priority = "320"
      name = "Allow github runner ips"
      ip_address = "20.62.150.64/29"
      action = "Allow"
    }
    ip_restriction {
      priority = "330"
      name = "Allow github runner ips"
      ip_address = "4.156.190.128/29"
      action = "Allow"
    }
    ip_restriction {
      priority = "340"
      name = "Allow github runner ips"
      ip_address = "20.1.254.152/29"
      action = "Allow"
    }
    ip_restriction {
      priority = "350"
      name = "Allow github runner ips"
      ip_address = "20.246.150.176/29"
      action = "Allow"
    }
    ip_restriction {
      priority = "360"
      name = "Allow github runner ips"
      ip_address = "4.152.59.8/29"
      action = "Allow"
    }
    ip_restriction_default_action = "Deny"
    scm_ip_restriction_default_action = "Deny"
    scm_ip_restriction {
      name       = "Deny all access"
      ip_address = "0.0.0.0/0"
      action     = "Deny"
      priority   = "400"
    }
  }

  lifecycle {
    ignore_changes = [
      tags # ignore since there are tags that gets created for app insights by azure
    ]
  }
}

data "aws_dynamodb_table" "common_image_table" {
  name         = "${local.namespaces-}golden-images-metadata"
}

resource "azurerm_role_assignment" "azu_build_storage" {
  scope                = azurerm_storage_account.azu_build.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.azu_build.identity[0].principal_id
}

resource "azurerm_role_assignment" "azu_build_virtual_machines" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_linux_function_app.azu_build.identity[0].principal_id
}

resource "azurerm_role_assignment" "azu_build_security_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Security Reader"
  principal_id         = azurerm_linux_function_app.azu_build.identity[0].principal_id
}

resource "azurerm_key_vault_access_policy" "azu_build_key_vault_secrets" {
  key_vault_id = azurerm_key_vault.build.id

  tenant_id = azurerm_linux_function_app.azu_build.identity[0].tenant_id
  object_id = azurerm_linux_function_app.azu_build.identity[0].principal_id
  depends_on = [
    azurerm_linux_function_app.azu_build
  ]

  key_permissions = [
    "Decrypt",
    "Encrypt",
    "Get",
    "List",
  ]

  secret_permissions = [
    "Get",
    "List",
  ]
}

# Deploy Function App

resource "time_sleep" "azu_build" {
  create_duration = "15s"

  triggers = local.deploy_azu_build

  depends_on = [
    azurerm_linux_function_app.azu_build
  ]
}

resource "null_resource" "azu_build" {
  triggers = local.deploy_azu_build

  provisioner "local-exec" {
    command = "${path.module}/deploy-function-app.sh --subscription-id ${var.azu_sub} --tenant-id ${var.azu_tenant} --client-id ${var.azu_client_id} --client-secret ${var.azu_client_secret} --resource-group ${azurerm_linux_function_app.azu_build.resource_group_name} --function-app ${azurerm_linux_function_app.azu_build.name} --src-folder ${local.azu_build_name} --src-path ${path.module}"
  }

  depends_on = [
    time_sleep.azu_build,
    null_resource.azure_function_core_tools
  ]
}

resource "null_resource" "azure_function_core_tools" {
  triggers = {
    change_every_time = timestamp()
  }

  provisioner "local-exec" {
    command = "chmod +x ${path.module}/azure_function_core_tools.sh;${path.module}/azure_function_core_tools.sh"
  }
}
data "aws_secretsmanager_secret" "image_api_url" {
  name = "${local.namespaces_}golden_image_api_url"
}

# Key Vault for VM SSH key

resource "azurerm_key_vault" "azu_build_ssh" {
  name                = "${local.namespace-}vm-ssh-kv"
  resource_group_name = "${local.build_resource_group_name}"
  location            = "${local.build_resource_group_location}"
  tenant_id           = data.azuread_client_config.current.tenant_id

  enabled_for_template_deployment = true
  purge_protection_enabled        = false
  soft_delete_retention_days      = 7
  sku_name                        = "standard"
}

resource "azurerm_key_vault_access_policy" "azuread_azu_build_ssh_policy" {
  key_vault_id = azurerm_key_vault.azu_build_ssh.id
  tenant_id = data.azuread_client_config.current.tenant_id
  object_id = data.azuread_client_config.current.object_id
  depends_on = [
    azurerm_key_vault.azu_build_ssh
  ]
  key_permissions = [
    "Backup",
    "Create",
    "Decrypt",
    "Delete",
    "Encrypt",
    "Get",
    "Import",
    "List",
    "Purge",
    "Recover",
    "Restore",
    "Sign",
    "UnwrapKey",
    "Release",
    "Rotate",
    "GetRotationPolicy",
    "SetRotationPolicy"
  ]
  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Backup",
    "Restore",
    "Purge"
  ]
  storage_permissions = [
    "Get"
  ]
}

resource "azurerm_key_vault_access_policy" "azu_build_key_vault_ssh_key_secrets" {
  key_vault_id = azurerm_key_vault.azu_build_ssh.id

  tenant_id = azurerm_linux_function_app.azu_build.identity[0].tenant_id
  object_id = azurerm_linux_function_app.azu_build.identity[0].principal_id
  depends_on = [
    azurerm_linux_function_app.azu_build
  ]

  key_permissions = [
    "Decrypt",
    "Encrypt",
    "Get",
    "List",
  ]

  secret_permissions = [
    "Get",
    "List",
  ]
}

# Generate SSH key

resource "tls_private_key" "az_build_vm_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_key_vault_secret" "az_build_vm_ssh_public_key" {
  key_vault_id = azurerm_key_vault.azu_build_ssh.id
  name         = "${local.namespace-}gim-ssh-pub-key"
  value        = tls_private_key.az_build_vm_ssh_key.public_key_openssh
  depends_on = [
    azurerm_key_vault_access_policy.azuread_azu_build_ssh_policy
  ]
}

resource "azurerm_key_vault_secret" "az_build_vm_ssh_private_key" {
  key_vault_id = azurerm_key_vault.azu_build_ssh.id
  name         = "${local.namespace-}gim-ssh-pri-key"
  value        = tls_private_key.az_build_vm_ssh_key.private_key_pem
  depends_on = [
    azurerm_key_vault_access_policy.azuread_azu_build_ssh_policy
  ]
}


data "azuread_group" "gim_azu_owner_group" {
  display_name = "${local.owner_group_name}"
  security_enabled = true
}


resource "azurerm_key_vault_access_policy" "azu_build_key_vault_group_access" {
  key_vault_id = azurerm_key_vault.azu_build_ssh.id

  tenant_id = azurerm_linux_function_app.azu_build.identity[0].tenant_id
  object_id = data.azuread_group.gim_azu_owner_group.object_id
  depends_on = [
    azurerm_linux_function_app.azu_build
  ]

  key_permissions = [
    "Decrypt",
    "Encrypt",
    "Get",
    "List",
  ]

  secret_permissions = [
    "Get",
    "List",
  ]
}

resource "azurerm_storage_container" "azubuild_snowAgent_Container" {
  count                 = local.is_local? 0: 1
  name                  = "${local.namespaces-}snow-agent"
  storage_account_name  = azurerm_storage_account.azu_build.name
  container_access_type = "private"
}

data "azuread_group" "snowAgentAzureADGroup" {
  display_name     = "AZU_ITAMCloudSnowInvAgents"
  security_enabled = true
}

resource "azurerm_role_assignment" "azubuild_snowAgent_storage_access" {
  count                = local.is_local? 0: 1
  scope                = azurerm_storage_account.azu_build.id
  role_definition_name = "Reader"
  principal_id         = data.azuread_group.snowAgentAzureADGroup.object_id
}

resource "azurerm_role_assignment" "azubuild_snowAgent_Container_access" {
  count                = local.is_local? 0: 1
  scope                = azurerm_storage_container.azubuild_snowAgent_Container[0].resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_group.snowAgentAzureADGroup.object_id
}

data "azuread_service_principal" "Golden_images_sp" {
  display_name = "hcc_goldenimages_poc_azu_build"
}

resource "azurerm_role_assignment" "golden_images_sp_access_on_azubuild_storage" {
  count                = local.is_local? 0: 1
  scope                = azurerm_storage_container.azubuild_snowAgent_Container[0].resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_service_principal.Golden_images_sp.object_id
}
data "azurerm_storage_container" "poc_snow_container" {
  count = local.is_local? 1: 0
  name                 = "snow-agent"
  storage_account_name = "pocazubuildfunc"
}

resource "azurerm_role_assignment" "managed_identity_snow_access" {
  count = local.is_local? 1: 0
  scope                = data.azurerm_storage_container.poc_snow_container[0].resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.managed_identity.principal_id
}
