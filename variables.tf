variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}
variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}
variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}
variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}
variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}
variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}
variable "prometheus_version" {
  type        = string
  default     = "3.15.1"
  description = "Prometheus release to install, without the leading v."
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.]+)?$", var.prometheus_version))
    error_message = "prometheus_version is a release number without the leading v, such as \"3.15.1\"."
  }
}
variable "checksums" {
  type        = map(string)
  description = "SHA-256 of the release tarball for each architecture, from the release's sha256sums.txt. Change these with prometheus_version."
  default = {
    amd64 = "6a726885328ad9efebbf36e876ce2fb6225468a71fd1e7ce3ba666d5f4d97a84"
    arm64 = "ceb6d21493c37ca0b4513b147642797c68cf39a0f50a444d50e1e80c74f21b26"
  }
}
variable "listen_address" {
  type        = string
  default     = "127.0.0.1:9090"
  description = "Address and port Prometheus serves its UI and API on. \":9090\" listens on every address."
  validation {
    condition     = can(regex("^(\\[[0-9A-Fa-f:.]+\\]|[0-9A-Za-z.-]*):[0-9]{1,5}$", var.listen_address))
    error_message = "listen_address is HOST:PORT, such as \"127.0.0.1:9090\", \"[::1]:9090\" or \":9090\"."
  }
}
variable "scrape_interval" {
  type        = string
  default     = "15s"
  description = "How often Prometheus scrapes every target and evaluates rules, such as \"15s\" or \"1m\"."
  validation {
    condition     = can(regex("^([0-9]+(ms|s|m|h|d|w|y))+$", var.scrape_interval))
    error_message = "scrape_interval is a Prometheus duration, such as \"15s\", \"1m\" or \"1m30s\"."
  }
}
variable "retention" {
  type        = string
  default     = "15d"
  description = "How long Prometheus keeps samples before deleting them, such as \"15d\" or \"90d\"."
  validation {
    condition     = can(regex("^([0-9]+(ms|s|m|h|d|w|y))+$", var.retention))
    error_message = "retention is a Prometheus duration, such as \"15d\" or \"26w\"."
  }
}
variable "scrape_targets" {
  type        = map(list(string))
  default     = {}
  description = "Scrape jobs: a map of job names to lists of HOST:PORT targets, such as { node = [\"10.0.0.5:9100\"] }. Prometheus always scrapes itself as the prometheus job."
  validation {
    condition     = alltrue([for job in keys(var.scrape_targets) : can(regex("^[a-zA-Z_][a-zA-Z0-9_-]*$", job)) && job != "prometheus"])
    error_message = "Job names start with a letter or _, then letters, digits, - and _, and can't be prometheus, which is Prometheus's own job."
  }
  validation {
    condition     = alltrue(flatten([for t in values(var.scrape_targets) : [for target in t : can(regex("^(\\[[0-9A-Fa-f:.]+\\]|[0-9A-Za-z.-]+):[0-9]{1,5}$", target))]]))
    error_message = "Each target is HOST:PORT, such as \"10.0.0.5:9100\" or \"db1.internal:9187\", without http://."
  }
}
variable "extra_args" {
  type        = list(string)
  default     = []
  description = "More command-line flags for Prometheus, such as [\"--web.enable-admin-api\"]."
}
