// Logging configuration for debugging
logging {
  level  = "info"
  format = "logfmt"
}

// Live debugging configuration
livedebugging {
  enabled = true
}

// Node exporter for system metrics
prometheus.exporter.unix "willy" {
  procfs_path = "/host/proc"
  sysfs_path  = "/host/sys"
  rootfs_path = "/host"

  enable_collectors = ["meminfo"]
  disable_collectors = ["ipvs", "btrfs", "infiniband", "xfs", "zfs"]

  filesystem {
    fs_types_exclude     = "^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|tmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$"
    mount_points_exclude = "^/(dev|proc|run/credentials/.+|sys|var/lib/docker/.+)($|/)"
    mount_timeout        = "5s"
  }

  netclass {
    ignored_devices = "^(veth.*|cali.*|[a-f0-9]{15})$"
  }

  netdev {
    device_exclude = "^(veth.*|cali.*|[a-f0-9]{15})$"
  }
}

// Scrape node exporter metrics
prometheus.scrape "willy_metrics" {
  targets    = prometheus.exporter.unix.willy.targets
  forward_to = [prometheus.remote_write.default.receiver]
  scrape_interval = "15s"
}

// Scrape PVE exporter metrics
prometheus.scrape "pve_metrics" {
  targets = [{
    __address__ = "pve-exporter:9221",
  }]
  forward_to = [prometheus.remote_write.default.receiver]
  scrape_interval = "30s"
  job_name = "proxmox"
  metrics_path = "/pve"
  params = {
    target = ["outerheaven.network"],
    cluster = ["1"],
    node = ["1"],
    module = ["default"],
  }
}

// Scrape Watchtower metrics (local only)
prometheus.scrape "watchtower_local" {
  targets = [{
    __address__ = "watchtower:8080",
    host = "willy",
    service = "watchtower",
  }]
  forward_to = [prometheus.remote_write.default.receiver]
  scrape_interval = "30s"
  job_name = "watchtower"
  metrics_path = "/v1/metrics"
  bearer_token = sys.env("WATCHTOWER_TOKEN")
}

// Scrape Alloy self-metrics
prometheus.scrape "alloy_self" {
  targets = [{
    __address__ = "127.0.0.1:12345",
    host = "willy",
    service = "alloy",
  }]
  forward_to = [prometheus.remote_write.default.receiver]
  scrape_interval = "15s"
  job_name = "alloy"
  metrics_path = "/metrics"
}

// Send metrics to Prometheus (local LGTM)
prometheus.remote_write "default" {
  endpoint {
    url = "http://lgtm:9090/api/v1/write"
  }
}

// ========= SYSLOG FROM PROXMOX VMs/LXCs =========
loki.source.syslog "proxmox_vms" {
  listener {
    address = "0.0.0.0:1514"
    labels = {
      job = "proxmox-vms",
      platform = "proxmox-guest",
      protocol = "tcp",
    }
  }
  listener {
    address = "0.0.0.0:1514"
    protocol = "udp"
    labels = {
      job = "proxmox-vms",
      platform = "proxmox-guest",
      protocol = "udp",
    }
  }
  forward_to = [loki.process.parse_proxmox_vm_logs.receiver]
}

// Process Proxmox VM/LXC logs
loki.process "parse_proxmox_vm_logs" {
  stage.static_labels {
    values = {
      platform = "proxmox-guest",
      source = "syslog",
    }
  }

  // Extract hostname from syslog message
  stage.regex {
    expression = `^<\d+>.*?\s+(?P<vm_hostname>\S+)\s+`
  }

  // Extract service/program name
  stage.regex {
    expression = `\s+(?P<program>[^:\[\s]+)(?:\[(?P<pid>\d+)\])?:\s*`
  }

  // Extract facility and severity
  stage.regex {
    expression = `^<(?P<priority>\d+)>`
  }

  // Calculate facility and severity from priority
  stage.template {
    source = "facility"
    template = "{{ div .priority 8 }}"
  }

  stage.template {
    source = "severity"
    template = "{{ mod .priority 8 }}"
  }

  stage.labels {
    values = {
      vm_hostname = "",
      program = "",
      pid = "",
      facility = "",
      severity = "",
    }
  }

  forward_to = [loki.write.default.receiver]
}

// Docker container discovery
discovery.docker "willy_containers" {
  host = "unix:///var/run/docker.sock"
}

// Relabel docker containers for logs
discovery.relabel "willy_docker_logs" {
  targets = discovery.docker.willy_containers.targets

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex = "/(.*)"
    target_label = "container"
  }

  rule {
    source_labels = ["__meta_docker_container_id"]
    target_label = "container_id"
  }

  rule {
    source_labels = ["__meta_docker_container_image"]
    target_label = "image"
  }

  rule {
    source_labels = ["__meta_docker_container_label_com_docker_compose_service"]
    target_label = "compose_service"
  }

  rule {
    target_label = "host"
    replacement = "willy"
  }

  rule {
    target_label = "job"
    replacement = "docker/willy"
  }
}

// Collect Docker container logs
loki.source.docker "willy_containers" {
  host             = "unix:///var/run/docker.sock"
  targets          = discovery.relabel.willy_docker_logs.output
  labels           = { platform = "docker", host = "willy" }
  forward_to       = [loki.write.default.receiver]
  refresh_interval = "5s"
}

// Send logs to Loki (local LGTM)
loki.write "default" {
  endpoint {
    url = "http://lgtm:3100/loki/api/v1/push"
  }
}
