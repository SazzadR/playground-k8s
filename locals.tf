locals {
    env                 = "sandbox"
    resource_prefix     = "${local.env}-playground"
    region              = "us-east-1"
    availability_zone_1 = "us-east-1a"
    availability_zone_2 = "us-east-1b"
    eks_cluster_name    = "${local.resource_prefix}-cluster"
    eks_version         = "1.32"
}
