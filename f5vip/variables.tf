variable "bigip_address" {
  description = "BIG-IP management address (https://x.x.x.x)"
  type        = string
}

variable "bigip_username" {
  description = "BIG-IP admin username"
  type        = string
  default     = "admin"
}

variable "bigip_password" {
  description = "BIG-IP admin password"
  type        = string
  sensitive   = true
}

variable "partition" {
  description = "BIG-IP partition"
  type        = string
  default     = "Common"
}

# Talos worker + control-plane node IPs
variable "backend_nodes" {
  description = "K8s node IPs for pool members"
  type        = list(string)
  default = [
    "172.16.10.130",
    "172.16.10.132",
    "172.16.10.133",
    "172.16.10.136",
  ]
}
