output "aws_region" {
    description = "AWS region."
    value       = local.region
}


output "eks_cluster_name" {
    description = "The name of the EKS cluster."
    value       = module.eks.cluster_name
}
