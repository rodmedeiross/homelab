// Logging configuration for debugging
logging {
  level  = "info"
  format = "logfmt"
}

// Node exporter for system metrics
prometheus.exporter.unix "mobydick" {
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
prometheus.scrape "mobydick_metrics" {
  targets    = prometheus.exporter.unix.mobydick.targets
  forward_to = [prometheus.remote_write.default.receiver]
  scrape_interval = "15s"
}

// Send metrics to Prometheus (LGTM)
prometheus.remote_write "default" {
  endpoint {
    url = "http://10.10.1.20:9090/api/v1/write"
  }
}

// Docker container discovery
discovery.docker "mobydick_containers" {
  host = "unix:///var/run/docker.sock"
}

// Relabel docker containers for logs
discovery.relabel "mobydick_docker_logs" {
  targets = discovery.docker.mobydick_containers.targets

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
    replacement = "mobydick"
  }

  rule {
    target_label = "job"
    replacement = "docker/mobydick"
  }
}

// Collect Docker container logs
loki.source.docker "mobydick_containers" {
  host             = "unix:///var/run/docker.sock"
  targets          = discovery.relabel.mobydick_docker_logs.output
  labels           = { platform = "docker", host = "mobydick" }
  forward_to       = [loki.write.default.receiver]
  refresh_interval = "5s"
}

// Send logs to Loki (LGTM)
loki.write "default" {
  endpoint {
    url = "http://10.10.1.20:3100/loki/api/v1/push"
  }
}
