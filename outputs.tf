output "config_file" {
  description = "Path of the configuration file the circuit writes on each host."
  value       = local.config_file
}

output "jobs" {
  description = "Names of the scrape jobs, prometheus first."
  value       = concat(["prometheus"], keys(var.scrape_targets))
}
