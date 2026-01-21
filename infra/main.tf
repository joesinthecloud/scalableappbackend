data "aws_availability_zones" "available" {
  state = "available"

  # Keep only standard regional AZs, exclude Local Zones and other zone types.
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

locals {
  name = "${var.project}-${var.env}"

  # Force standard AZs only
  azs = ["us-east-1a", "us-east-1b"]

  vpc_cidr = "10.0.0.0/16"

  public_subnet_cidrs  = [cidrsubnet(local.vpc_cidr, 8, 0), cidrsubnet(local.vpc_cidr, 8, 1)]
  private_subnet_cidrs = [cidrsubnet(local.vpc_cidr, 8, 10), cidrsubnet(local.vpc_cidr, 8, 11)]
}

resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${local.name}-vpc"
    Project = var.project
    Env     = var.env
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${local.name}-igw"
    Project = var.project
    Env     = var.env
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  availability_zone       = local.azs[count.index]
  cidr_block              = local.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${local.name}-public-${count.index}"
    Tier    = "public"
    Project = var.project
    Env     = var.env
  }
}

resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  availability_zone       = local.azs[count.index]
  cidr_block              = local.private_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name    = "${local.name}-private-${count.index}"
    Tier    = "private"
    Project = var.project
    Env     = var.env
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${local.name}-public-rt"
    Project = var.project
    Env     = var.env
  }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${local.name}-private-rt"
    Project = var.project
    Env     = var.env
  }
}

resource "aws_route_table_association" "private_assoc" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
