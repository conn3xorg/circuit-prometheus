# Facts give each host's architecture, which picks the release tarball.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }
}

locals {
  goarch  = { x86_64 = "amd64", aarch64 = "arm64" }
  arch    = { for name, f in data.conn3x_host.facts : name => local.goarch[f.arch] }
  release = { for name, a in local.arch : name => "prometheus-${var.prometheus_version}.linux-${a}" }
  bin     = { for name, r in local.release : name => "/opt/prometheus/${r}" }

  config_file = "/etc/prometheus/prometheus.yml"
  # promtool checks this copy before it replaces the live file, so a config
  # Prometheus would reject never reaches it.
  staged_file = "/etc/prometheus/prometheus.yml.conn3x"
  data_dir    = "/var/lib/prometheus"

  listen_host = regex("^(.*):[0-9]+$", var.listen_address)[0]
  listen_port = tonumber(regex(":([0-9]+)$", var.listen_address)[0])
  # Prometheus scrapes itself. A wildcard address isn't one it can dial.
  self_target = contains(["", "0.0.0.0", "[::]"], local.listen_host) ? "localhost:${local.listen_port}" : var.listen_address

  ready_url = "http://${local.self_target}/-/ready"

  scrape_configs = concat(
    [{ job_name = "prometheus", static_configs = [{ targets = [local.self_target] }] }],
    [for job, targets in var.scrape_targets : { job_name = job, static_configs = [{ targets = targets }] }],
  )
  config = "# Written by Conn3x. Changes here are overwritten on the next apply.\n${yamlencode({
    global         = { scrape_interval = var.scrape_interval, evaluation_interval = var.scrape_interval }
    scrape_configs = local.scrape_configs
  })}"

  flags = [
    "--config.file=${local.config_file}",
    "--storage.tsdb.path=${local.data_dir}",
    "--storage.tsdb.retention.time=${var.retention}",
    "--web.listen-address=${var.listen_address}",
  ]
}

circuit "prometheus" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Minimal images can lack any of these.
  step "tools" {
    for_each = toset(["curl", "tar", "gzip"])
    package {
      name = item.value
    }
  }

  step "user" {
    user {
      name   = "prometheus"
      system = true
      home   = local.data_dir
      shell  = "/usr/sbin/nologin"
    }
  }

  step "data" {
    directory {
      path  = local.data_dir
      owner = "prometheus"
      group = "prometheus"
      mode  = "0750"
    }
  }

  step "download" {
    download {
      url    = "https://github.com/prometheus/prometheus/releases/download/v${var.prometheus_version}/${local.release[each.key]}.tar.gz"
      sha256 = var.checksums[local.arch[each.key]]
      dest   = "${local.bin[each.key]}.tar.gz"
    }
  }

  step "unpack" {
    archive {
      src     = "${local.bin[each.key]}.tar.gz"
      dest    = "/opt/prometheus"
      creates = "${local.bin[each.key]}/prometheus"
    }
  }

  step "etc" {
    directory {
      path = "/etc/prometheus"
    }
  }

  step "staged" {
    file {
      path    = local.staged_file
      content = local.config
    }
  }

  # Checks the staged copy, puts it live and reloads Prometheus if it's
  # running. On the first apply it isn't yet, and starts with this file.
  step "config" {
    command {
      command = "${local.bin[each.key]}/promtool check config ${local.staged_file} && install -m 644 ${local.staged_file} ${local.config_file} && if systemctl -q is-active prometheus; then systemctl reload prometheus; fi"
      unless  = "echo '${sha256(local.config)}  ${local.config_file}' | sha256sum -c --status"
    }
  }

  step "unit" {
    file {
      path    = "/etc/systemd/system/prometheus.service"
      content = <<-EOT
        [Unit]
        Description=Prometheus
        After=network-online.target
        Wants=network-online.target

        [Service]
        User=prometheus
        Group=prometheus
        ExecStart=${join(" ", concat(["${local.bin[each.key]}/prometheus"], local.flags, var.extra_args))}
        ExecReload=/bin/kill -HUP $MAINPID
        Restart=on-failure
        NoNewPrivileges=true
        ProtectSystem=strict
        ProtectHome=true
        ReadWritePaths=${local.data_dir}

        [Install]
        WantedBy=multi-user.target
      EOT
    }
  }

  # Restarts Prometheus when the unit changes. This is a step rather than a
  # handler because handlers run after every step, and the ready check below
  # has to see Prometheus running with the new unit.
  step "restart" {
    command {
      command  = "systemctl daemon-reload && systemctl restart prometheus"
      triggers = { unit = conn3x_file.prometheus__unit[each.key].revision }
    }
  }

  step "running" {
    service {
      name    = "prometheus"
      state   = "started"
      enabled = true
    }
  }

  # Waits for Prometheus to answer on its own ready endpoint. Checking only
  # that something listens on the port isn't enough: on Rocky Linux cloud
  # images cockpit.socket holds 9090, and Prometheus would fail to bind.
  step "ready" {
    command {
      command = "for _ in $(seq 60); do curl -sf ${local.ready_url} | grep -q Ready && exit 0; sleep 1; done; echo 'Prometheus is not answering on ${var.listen_address}. Is another service, such as cockpit.socket, on that port? See journalctl -u prometheus.' >&2; exit 1"
      unless  = "curl -sf ${local.ready_url} | grep -q Ready"
    }
  }
}
