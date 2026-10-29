variable "port" {
  type    = number
  default = 2222
}

variable "scrape_interval" {
  type    = string
  default = "10s"
}

locals {
  hosts = { box = "127.0.0.1" }
}

# Something to scrape: node_exporter on the same host, from its own circuit.
module "node_exporter" {
  source = "github.com/conn3xorg/circuit-node-exporter?ref=v0.1.0"

  hosts                = local.hosts
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"
}

module "prometheus" {
  source = "../.."

  hosts                = local.hosts
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  scrape_interval = var.scrape_interval
  retention       = "7d"

  # Prometheus runs on the same host as node_exporter, so it scrapes it on
  # localhost, not on the address Conn3x logs in on.
  scrape_targets = {
    node = ["localhost:9100"]
  }
}

output "jobs" {
  value = module.prometheus.jobs
}
