output "generated_filename" {
  description = "Full path of the generated report file on disk"
  value       = local_file.report.filename
}

output "unique_suffix" {
  description = "Random 6-character suffix used in the filename"
  value       = random_string.suffix.result
}

output "file_content_preview" {
  description = "Summary line confirming what was created"
  value       = local.file_content
}
