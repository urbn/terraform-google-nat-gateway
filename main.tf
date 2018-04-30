/*
 * Copyright 2017 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

data "template_file" "nat-startup-script" {
  template = <<EOF
#!/bin/bash -xe

# Enable ip forwarding and nat
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

apt-get update

# Install nginx for instance http health check
apt-get install -y nginx

ENABLE_SQUID="${var.squid_enabled}"

if [[ "$ENABLE_SQUID" == "true" ]]; then
  apt-get install -y squid3

  cat - > /etc/squid3/squid.conf <<'EOM'
${file("${var.squid_config == "" ? "${format("%s/config/squid.conf", path.module)}" : var.squid_config}")}
EOM

  systemctl reload squid3
fi
EOF
}

data "google_compute_network" "network" {
  name    = "${var.network}"
  project = "${var.network_project == "" ? var.project : var.network_project}"
}

data "google_compute_address" "default" {
  name    = "${element(concat(google_compute_address.default.*.name, list("${var.ip_address_name}")), 0)}"
  project = "${var.network_project == "" ? var.project : var.network_project}"
  region  = "${var.region}"
}

module "nat-gateway" {
  source            = "github.com/urbn/terraform-google-managed-instance-group"
  project           = "${var.project}"
  region            = "${var.region}"
  zone              = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"
  network           = "${var.network}"
  subnetwork        = "${var.subnetwork}"
  target_tags       = ["${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}-egress"]
  machine_type      = "${var.machine_type}"
  name              = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}-egress"
  compute_image     = "debian-cloud/debian-8"
  size              = 1
  network_ip        = "${var.ip}"
  can_ip_forward    = "true"
  service_port      = "80"
  service_port_name = "http"
  startup_script    = "${data.template_file.nat-startup-script.rendered}"
  wait_for_instances = true

  access_config = [
    {
      nat_ip = "${data.google_compute_address.default.address}"
    },
  ]
}

resource "google_compute_route" "nat-gateway" {
  name                   = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}-egress"
  project                = "${var.project}"
  dest_range             = "0.0.0.0/0"
  network                = "${data.google_compute_network.network.self_link}"
  next_hop_instance      = "${(length(module.nat-gateway.instances) > 0 && length(module.nat-gateway.instances[0]) > 0) ? element(split("/", element(concat(module.nat-gateway.instances[0], list("")), 0)), 10): ""}"
  next_hop_instance_zone = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"
  tags                   = ["${compact(concat(list("${var.region}-egress"), var.tags))}"]
  priority               = "${var.route_priority}"
}

resource "google_compute_firewall" "nat-gateway" {
  name    = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}-egress"
  network = "${var.network}"
  project = "${var.project}"

  allow {
    protocol = "all"
  }

  source_tags = ["${compact(concat(list("${var.region}-egress", "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}-egress"), var.tags))}"]
  target_tags = ["${compact(concat(list("${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}-egress"), var.tags))}"]
}

resource "google_compute_address" "default" {
  count   = "${var.ip_address_name == "" ? 1 : 0}"
  name    = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}-egress"
  project = "${var.project}"
  region  = "${var.region}"
}
