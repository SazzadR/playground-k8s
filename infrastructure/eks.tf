resource "aws_iam_role" "eks_cluster" {
    name = "${local.eks_cluster_name}-role"

    assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Principal": {
                "Service": "eks.amazonaws.com"
            }
        }
    ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    role       = aws_iam_role.eks_cluster.name
}

resource "aws_eks_cluster" "main" {
    name     = local.eks_cluster_name
    version  = local.eks_version
    role_arn = aws_iam_role.eks_cluster.arn

    vpc_config {
        endpoint_private_access = false
        endpoint_public_access  = true

        subnet_ids = [
            aws_subnet.private_1.id,
            aws_subnet.private_2.id
        ]
    }

    access_config {
        authentication_mode                         = "API"
        bootstrap_cluster_creator_admin_permissions = true
    }

    depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

resource "aws_iam_role" "eks_node_group" {
    name = "${local.eks_cluster_name}-node-group-role"

    assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            }
        }
    ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_ec2_container_registry_read_only_policy" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    role       = aws_iam_role.eks_node_group.name
}

resource "aws_eks_node_group" "general" {
    node_group_name = "general"
    cluster_name    = aws_eks_cluster.main.name
    node_role_arn   = aws_iam_role.eks_node_group.arn

    subnet_ids = [
        aws_subnet.private_1.id,
        aws_subnet.private_2.id
    ]

    capacity_type = "ON_DEMAND"
    instance_types = ["t3.small"]

    scaling_config {
        desired_size = 1
        max_size     = 3
        min_size     = 1
    }

    update_config {
        max_unavailable = 1
    }

    depends_on = [
        aws_iam_role_policy_attachment.eks_worker_node_policy,
        aws_iam_role_policy_attachment.eks_cni_policy,
        aws_iam_role_policy_attachment.eks_ec2_container_registry_read_only_policy
    ]

    # Allow external changes without Terraform plan difference. Used for scaling.
    lifecycle {
        ignore_changes = [scaling_config[0].desired_size]
    }
}

resource "helm_release" "metrics_server" {
    name = "metrics-server"

    repository = "https://kubernetes-sigs.github.io/metrics-server/"
    chart      = "metrics-server"
    namespace  = "kube-system"
    version    = "3.12.2"

    values = [
        file("${path.module}/values/metrics-server.yaml")
    ]

    depends_on = [aws_eks_node_group.general]
}

resource "aws_eks_addon" "pod_identity" {
    cluster_name  = aws_eks_cluster.main.name
    addon_name    = "eks-pod-identity-agent"
    addon_version = "v1.3.5-eksbuild.2"
}

resource "aws_iam_role" "eks_cluster_autoscaler" {
    name = "${aws_eks_cluster.main.name}-cluster-autoscaler"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "sts:AssumeRole",
                    "sts:TagSession"
                ]
                Principal = {
                    Service = "pods.eks.amazonaws.com"
                }
            }
        ]
    })
}

resource "aws_iam_policy" "eks_cluster_autoscaler" {
    name = "${aws_eks_cluster.main.name}-cluster-autoscaler"

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "autoscaling:DescribeAutoScalingGroups",
                    "autoscaling:DescribeAutoScalingInstances",
                    "autoscaling:DescribeLaunchConfigurations",
                    "autoscaling:DescribeScalingActivities",
                    "autoscaling:DescribeTags",
                    "ec2:DescribeImages",
                    "ec2:DescribeInstanceTypes",
                    "ec2:DescribeLaunchTemplateVersions",
                    "ec2:GetInstanceTypesFromInstanceRequirements",
                    "eks:DescribeNodegroup"
                ]
                Resource = "*"
            },
            {
                Effect = "Allow"
                Action = [
                    "autoscaling:SetDesiredCapacity",
                    "autoscaling:TerminateInstanceInAutoScalingGroup"
                ]
                Resource = "*"
            },
        ]
    })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_autoscaler" {
    policy_arn = aws_iam_policy.eks_cluster_autoscaler.arn
    role       = aws_iam_role.eks_cluster_autoscaler.name
}

resource "aws_eks_pod_identity_association" "eks_cluster_autoscaler" {
    cluster_name    = aws_eks_cluster.main.name
    namespace       = "kube-system"
    service_account = "cluster-autoscaler"
    role_arn        = aws_iam_role.eks_cluster_autoscaler.arn
}

resource "helm_release" "eks_cluster_autoscaler" {
    name = "autoscaler"

    repository = "https://kubernetes.github.io/autoscaler"
    chart      = "cluster-autoscaler"
    namespace  = "kube-system"
    version    = "9.37.0"

    set {
        name  = "rbac.serviceAccount.name"
        value = "cluster-autoscaler"
    }

    set {
        name  = "autoDiscovery.clusterName"
        value = aws_eks_cluster.main.name
    }

    set {
        name  = "awsRegion"
        value = local.region
    }

    depends_on = [helm_release.metrics_server]
}
