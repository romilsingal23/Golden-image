provisioner "shell" {
  inline = [
    "wget -O Dynatrace-OneAgent.sh \"https://vbk56183.live.dynatrace.com/api/v1/deployment/installer/agent/unix/default/version/1.299.50.20240930-123825?arch=x86&networkZone=gcp.us.east4.nonprod\" --header=\"Authorization: Api-Token $$$$$$$$$$$$$$$$$$$$$$\"",
    "chmod +x Dynatrace-OneAgent.sh",
    "/bin/sh Dynatrace-OneAgent.sh --set-monitoring-mode=fullstack --set-app-log-content-access=true --set-network-zone=gcp.us.east4.nonprod --set-host-group=AG_SYN_NONPROD_GCP"
  ]
  }
