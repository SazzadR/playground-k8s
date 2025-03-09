terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 5.0"
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

data "aws_eks_cluster" "main" {
    name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "main" {
    name = aws_eks_cluster.main.name
}

provider "helm" {
    kubernetes {
        host  = data.aws_eks_cluster.main.endpoint
        token = data.aws_eks_cluster_auth.main.token
        cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority.0.data)
    }
}
