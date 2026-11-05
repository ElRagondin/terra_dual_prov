output "bucket_name" {
  description = "Nom du bucket de diagnostics"
  value       = ovh_cloud_storage_object_bucket.diagnostics.name
}
