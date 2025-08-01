terraform {
  backend "gcs" {
    bucket = "ajkll_terraform_state"
    prefix = "terraform/lab-iac/"
  }
}