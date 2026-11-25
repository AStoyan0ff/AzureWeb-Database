terraform {
  backend "azurerm" {
    storage_account_name = "sttaskboard927eb9bf62"
    container_name       = "tfstate"
    key                  = "taskboard.tfstate"
    use_azuread_auth     = true
  }
}