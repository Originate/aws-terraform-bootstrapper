output "region" {
  value = module.backend.region
}

output "bucket_name" {
  value = module.backend.bucket_name
}

output "dynamodb_table_name" {
  value = module.backend.dynamodb_table_name
}

output "profile" {
  value = module.backend.profile
}
