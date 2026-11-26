terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_integer" "suffix" {
  min = 10000
  max = 99999
}

resource "azurerm_resource_group" "taskboard" {
  name     = "rg-taskboard-${random_integer.suffix.result}"
  location = "Spain Central"

  tags = {
    managed_by = "terraform"
  }
}

variable "sql_admin_password" {
  description = "Password for the Azure SQL administrator"
  type        = string
  sensitive   = true
}

resource "azurerm_mssql_server" "taskboard" {
  name                         = "sql-taskboard-${random_integer.suffix.result}"
  resource_group_name          = azurerm_resource_group.taskboard.name
  location                     = azurerm_resource_group.taskboard.location
  version                      = "12.0"
  administrator_login          = "taskboardadmin"
  administrator_login_password = var.sql_admin_password
}

resource "azurerm_mssql_database" "taskboard" {
  name                 = "TaskBoard"
  server_id            = azurerm_mssql_server.taskboard.id
  collation            = "SQL_Latin1_General_CP1_CI_AS"
  license_type         = "LicenseIncluded"
  sku_name             = "Basic"
  zone_redundant       = false
  storage_account_type = "Local"
}

resource "azurerm_mssql_firewall_rule" "allow_azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.taskboard.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_service_plan" "taskboard" {
  name                = "plan-taskboard-${random_integer.suffix.result}"
  resource_group_name = azurerm_resource_group.taskboard.name
  location            = azurerm_resource_group.taskboard.location
  os_type             = "Linux"
  sku_name            = "F1"
}

resource "azurerm_linux_web_app" "taskboard" {
  name                = "taskboard-${random_integer.suffix.result}"
  resource_group_name = azurerm_resource_group.taskboard.name
  location            = azurerm_resource_group.taskboard.location
  service_plan_id     = azurerm_service_plan.taskboard.id
  https_only          = true

  app_settings = {
    PROJECT                        = "3.AzureWeb-DataBase/TaskBoard.WebApp/TaskBoard.WebApp.csproj"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
  }

  site_config {
    always_on = false

    application_stack {
      dotnet_version = "10.0"
    }
  }

  connection_string {
    name  = "DefaultConnection"
    type  = "SQLAzure"
    value = "Server=tcp:${azurerm_mssql_server.taskboard.fully_qualified_domain_name},1433;Database=${azurerm_mssql_database.taskboard.name};User ID=${azurerm_mssql_server.taskboard.administrator_login};Password='${replace(var.sql_admin_password, "'", "''")}';Encrypt=True;TrustServerCertificate=False;MultipleActiveResultSets=True;"
  }
}

resource "azurerm_app_service_source_control" "taskboard" {
  app_id                 = azurerm_linux_web_app.taskboard.id
  repo_url               = "https://github.com/AStoyan0ff/AzureWeb-Database.git"
  branch                 = "main"
  use_manual_integration = true

  depends_on = [azurerm_mssql_firewall_rule.allow_azure]
}

output "web_app_url" {
  value = "https://${azurerm_linux_web_app.taskboard.default_hostname}"
}