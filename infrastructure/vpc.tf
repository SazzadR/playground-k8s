resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"

    enable_dns_support   = true
    enable_dns_hostnames = true

    tags = {
        Name = "${local.resource_prefix}-vpc"
    }
}

resource "aws_internet_gateway" "main" {
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${local.resource_prefix}-igw"
    }
}

resource "aws_subnet" "private_1" {
    vpc_id            = aws_vpc.main.id
    cidr_block        = "10.0.1.0/24"
    availability_zone = local.availability_zone_1

    tags = {
        Name                                              = "${local.resource_prefix}-private-${local.availability_zone_1}"
        "kubernetes.io/role/internal-elb"                 = "1"
        "kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
    }
}

resource "aws_subnet" "private_2" {
    vpc_id            = aws_vpc.main.id
    cidr_block        = "10.0.2.0/24"
    availability_zone = local.availability_zone_2

    tags = {
        Name                                              = "${local.resource_prefix}-private-${local.availability_zone_2}"
        "kubernetes.io/role/internal-elb"                 = "1"
        "kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
    }
}

resource "aws_subnet" "public_1" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.0.3.0/24"
    availability_zone       = local.availability_zone_1
    map_public_ip_on_launch = true

    tags = {
        Name                                              = "${local.resource_prefix}-public-${local.availability_zone_1}"
        "kubernetes.io/role/elb"                          = "1"
        "kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
    }
}

resource "aws_subnet" "public_2" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.0.4.0/24"
    availability_zone       = local.availability_zone_2
    map_public_ip_on_launch = true

    tags = {
        Name                                              = "${local.resource_prefix}-public-${local.availability_zone_2}"
        "kubernetes.io/role/elb"                          = "1"
        "kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
    }
}

resource "aws_eip" "nat" {
    domain = "vpc"

    tags = {
        Name = "${local.resource_prefix}-nat-eip"
    }
}

resource "aws_nat_gateway" "main" {
    subnet_id     = aws_subnet.public_1.id
    allocation_id = aws_eip.nat.id

    tags = {
        Name = "${local.resource_prefix}-nat-gw"
    }

    depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private_rtb" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block     = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.main.id
    }

    tags = {
        Name = "${local.resource_prefix}-private-rtb"
    }
}

resource "aws_route_table" "public_rtb" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main.id
    }

    tags = {
        Name = "${local.resource_prefix}-public-rtb"
    }
}

resource "aws_route_table_association" "private_subnet_1_rta" {
    subnet_id      = aws_subnet.private_1.id
    route_table_id = aws_route_table.private_rtb.id
}

resource "aws_route_table_association" "private_subnet_2_rta" {
    subnet_id      = aws_subnet.private_2.id
    route_table_id = aws_route_table.private_rtb.id
}

resource "aws_route_table_association" "public_subnet_1_rta" {
    subnet_id      = aws_subnet.public_1.id
    route_table_id = aws_route_table.public_rtb.id
}

resource "aws_route_table_association" "public_subnet_2_rta" {
    subnet_id      = aws_subnet.public_2.id
    route_table_id = aws_route_table.public_rtb.id
}
