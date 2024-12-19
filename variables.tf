locals {
  namespaces- = var.environment == "local" ? "${var.namespace}-" : var.environment == "poc" ? "poc-" : "prod-"
  namespace-  = var.environment == "local" ? "${var.namespace}-" : ""
  namespaces_ = var.environment == "local" ? "${var.namespace}_" : var.environment == "poc" ? "poc_" : "prod_"
  namespace_  = var.environment == "local" ? "${var.namespace}_" : ""
  organization_id = "531591688136"
  project_number = var.project_number

}

variable "project_id" {
  type = string
}

variable "project_number" {
  type = number
}

variable "region" {
  type = string
}

variable "subnet_cidr_range" {
  type = string
}

variable "source_ranges" {
  type = list(string)
}

variable "target_tags" {
  type = list(string)
}

variable "namespace" {
  type = string
}

variable "environment" {
  type = string
}
