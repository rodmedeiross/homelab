// Logging configuration
logging {
  level  = "info"
  format = "logfmt"
}

// Live debugging
livedebugging {
  enabled = true
}

loki.source.journal "proxmox_systemd" {
  labels = {
    job = "proxmox-journal",
    host = "outerheaven",
    platform = "proxmox",
  }
  journal_fields = {
    "_SYSTEMD_UNIT" = [
      "pvedaemon.service",
      "pveproxy.service",
      "pvestatd.service",
      "pve-cluster.service",
      "corosync.service",
    ]
  }
  forward_to = [loki.write.to_lgtm.receiver]
}

loki.source.file "proxmox_logs" {
  targets = [
    // Standard Proxmox logs
    {
      __path__ = "/var/log/pve/tasks/*/*",
      job = "pve-tasks",
      log_type = "tasks",
      service = "proxmox",
    },
    {
      __path__ = "/var/log/pve-firewall.log",
      job = "pve-firewall",
      log_type = "firewall",
      service = "proxmox",
    },
    {
      __path__ = "/var/log/syslog",
      job = "pve-syslog",
      log_type = "system",
      service = "proxmox",
    },
    {
      __path__ = "/var/log/auth.log",
      job = "pve-auth",
      log_type = "auth",
      service = "proxmox",
    },

    {
      __path__ = "/var/log/vm-scheduler.log",
      job = "vm-scheduler",
      log_type = "scheduler",
      service = "custom-scripts",
    },
    {
      __path__ = "/var/run/qemu-gpu-guard/trace.log",
      job = "gpu-guard",
      log_type = "gpu-passthrough",
      service = "custom-scripts",
    },
  ]

  forward_to = [loki.process.parse_logs.receiver]
}

loki.process "parse_logs" {
  // Basic labels for all logs
  stage.static_labels {
    values = {
      host = "outerheaven",
      platform = "proxmox",
    }
  }

  stage.match {
    selector = `{job="vm-scheduler"}`

    // Extract main fields
    stage.regex {
      expression = `VM_SCHED: (?P<action>\w+) run (?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}); args: (?P<operation>\w+); host=(?P<hostname>\w+); VMIDS=\((?P<vmids>[^)]+)\)`
    }

    // For VM action logs
    stage.regex {
      expression = `VM_SCHED: (?P<action>Starting|Shutting down|VM) (?:VM )?(?P<vmid>\d+)`
    }

    // For result logs
    stage.regex {
      expression = `VM_SCHED: VM (?P<vmid>\d+) (?P<result>started successfully|stopped cleanly|already stopped)`
    }

    stage.labels {
      values = {
        action = "",
        operation = "",
        vmid = "",
        result = "",
      }
    }
  }

  stage.match {
    selector = `{job="gpu-guard"}`

    // General format parsing
    stage.regex {
      expression = `(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) (?P<event_type>\w+) phase=(?P<phase>[\w-]+) vmid=(?P<vmid>\d+)(?P<extra>.*)`
    }

    // Specific parsing for conflicts
    stage.regex {
      expression = `target_vmid=(?P<target_vmid>\d+)`
    }

    stage.regex {
      expression = `other_vmid=(?P<other_vmid>\d+)`
    }

    stage.regex {
      expression = `victim_vmid=(?P<victim_vmid>\d+)`
    }

    stage.regex {
      expression = `running_count=(?P<running_count>\d+)`
    }

    stage.regex {
      expression = `timeout=(?P<timeout>\w+)`
    }

    stage.labels {
      values = {
        event_type = "",
        phase = "",
        vmid = "",
        target_vmid = "",
        other_vmid = "",
        victim_vmid = "",
        running_count = "",
        timeout = "",
      }
    }
  }

  forward_to = [loki.write.to_lgtm.receiver]
}

// ========= SEND TO LGTM STACK =========
loki.write "to_lgtm" {
  endpoint {
    url = "http://10.10.1.20:3100/loki/api/v1/push"
  }
}
