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
  template = "${file("${format("%s/config/startup.sh", path.module)}")}"

  vars {
    squid_enabled = "${var.squid_enabled}"
    squid_config  = "${var.squid_config}"
    module_path   = "${path.module}"
  }
}

data "google_compute_network" "network" {
  name    = "${var.network}"
  project = "${var.network_project == "" ? var.project : var.network_project}"
}

data "google_compute_address" "default" {
  count   = "${var.ip_address_name == "" ? 0 : 1}"
  name    = "${var.ip_address_name}"
  project = "${var.network_project == "" ? var.project : var.network_project}"
  region  = "${var.region}"
}

module "nat-gateway" {
  source             = "git@github.com:urbn/terraform-google-managed-instance-group.git?ref=egress"
  module_enabled     = "${var.module_enabled}"
  project            = "${var.project}"
  region             = "${var.region}"
  zone               = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"
  network            = "${var.network}"
  subnetwork         = "${var.subnetwork}"
  target_tags        = ["${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}-egress"]
  instance_labels    = "${var.instance_labels}"
  machine_type       = "${var.machine_type}"
  name               = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}-egress"
  compute_image      = "debian-cloud/debian-9"
  size               = 1
  network_ip         = "${var.ip}"
  can_ip_forward     = "true"
  service_port       = "80"
  service_port_name  = "http"
  startup_script     = "${data.template_file.nat-startup-script.rendered}"
  wait_for_instances = true
  health_check_type  = "HTTP"
  metadata           = "${var.metadata}"
  ssh_source_ranges  = "${var.ssh_source_ranges}"

  access_config = [
    {
      nat_ip = "${element(concat(google_compute_address.default.*.address, data.google_compute_address.default.*.address, list("")), 0)}"
    },
  ]
}

resource "google_compute_route" "nat-gateway" {
  count                  = "${var.module_enabled ? 1 : 0}"
  name                   = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}-egress"
  project                = "${var.project}"
  dest_range             = "${var.dest_range}"
  network                = "${data.google_compute_network.network.self_link}"
  next_hop_instance      = "${(length(module.nat-gateway.instances) > 0 && length(module.nat-gateway.instances[0]) > 0) ? element(split("/", element(concat(module.nat-gateway.instances[0], list("")), 0)), 10): ""}"
  next_hop_instance_zone = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}"
  tags                   = ["${compact(concat(list("${var.region}-egress"), var.tags))}"]
  priority               = "${var.route_priority}"
}

resource "google_compute_firewall" "nat-gateway" {
  count   = "${var.module_enabled ? 1 : 0}"
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
  count   = "${var.module_enabled && var.ip_address_name == "" ? 1 : 0}"
  name    = "${var.zone == "" ? lookup(var.region_params["${var.region}"], "zone") : var.zone}-egress"
  project = "${var.project}"
  region  = "${var.region}"
}
