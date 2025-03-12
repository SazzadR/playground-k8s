output "aws_region" {
    description = "AWS region."
    value       = local.region
}

output "eks_cluster_name" {
    description = "The name of the EKS cluster."
    value       = module.eks.cluster_name
}

output "argocd_dns" {
    value = data.kubernetes_service.argocd_lb.status[0].load_balancer[0].ingress[0].hostname
}

output "argocd_admin_password" {
    value = nonsensitive(data.kubernetes_secret.argocd_admin_password.data["password"])
}
