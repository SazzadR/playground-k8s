terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 5.0"
        }

        kubectl = {
            source  = "gavinbunney/kubectl"
            version = "~> 1.19.0"
        }

        helm = {
            source  = "hashicorp/helm"
            version = "2.14.0"
        }
    }
}

provider "aws" {
    region = local.region
}

data "aws_eks_cluster_auth" "main" {
    name = module.eks.cluster_name
}

provider "helm" {
    kubernetes {
        host = module.eks.cluster_endpoint
        cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
        exec {
            api_version = "client.authentication.k8s.io/v1beta1"
            args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
            command     = "aws"
        }
    }
}

provider "kubectl" {
    host             = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    load_config_file = false
    exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
        command     = "aws"
    }
}
