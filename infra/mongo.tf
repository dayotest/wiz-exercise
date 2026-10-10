data "aws_ami" "ubuntu_old" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  # Focal is past standard support; its AMIs may be flagged deprecated
  include_deprecated = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

resource "random_password" "mongo_admin" {
  length  = 24
  special = false
}

resource "random_password" "mongo_app" {
  length  = 24
  special = false
}

resource "random_password" "app_secret" {
  length  = 32
  special = false
}

locals {
  mongo_app_user = "todoapp"
  backup_bucket  = "${var.project}-db-backups-${data.aws_caller_identity.current.account_id}"
}

# --- Intentionally weak: SSH open to the world --------------------------------
resource "aws_security_group" "mongo" {
  name        = "${var.project}-mongo"
  description = "MongoDB VM"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH from anywhere (INTENTIONAL WEAKNESS)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "MongoDB from EKS nodes only"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- Intentionally weak: overly permissive instance role ----------------------
resource "aws_iam_role" "mongo" {
  name = "${var.project}-mongo-vm"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "mongo_ec2_full" {
  role       = aws_iam_role.mongo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess" # can create VMs
}

resource "aws_iam_role_policy" "mongo_backup" {
  name = "backup-to-s3"
  role = aws_iam_role.mongo.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]
    }]
  })
}

resource "aws_iam_instance_profile" "mongo" {
  name = "${var.project}-mongo-vm"
  role = aws_iam_role.mongo.name
}

resource "aws_instance" "mongo" {
  ami                         = data.aws_ami.ubuntu_old.id
  instance_type               = var.mongo_instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.mongo.id]
  iam_instance_profile        = aws_iam_instance_profile.mongo.name
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name == "" ? null : var.ssh_key_name

  metadata_options {
    http_tokens = "optional" # IMDSv1 left on (INTENTIONAL WEAKNESS)
  }

  root_block_device {
    volume_size = 20
    encrypted   = false # INTENTIONAL WEAKNESS
  }

  user_data = templatefile("${path.module}/templates/mongo-userdata.sh.tftpl", {
    mongo_admin_password = random_password.mongo_admin.result
    mongo_app_user       = local.mongo_app_user
    mongo_app_password   = random_password.mongo_app.result
    backup_bucket        = local.backup_bucket
    region               = var.region
  })

  tags = { Name = "${var.project}-mongo" }
}

# --- Intentionally weak: public-read, public-list backup bucket ---------------
resource "aws_s3_bucket" "backups" {
  bucket        = local.backup_bucket
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  depends_on              = [aws_s3_bucket_ownership_controls.backups] # avoid concurrent bucket-config calls
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "backups_public" {
  bucket     = aws_s3_bucket.backups.id
  depends_on = [aws_s3_bucket_public_access_block.backups]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.backups.arn}/*"
      },
      {
        Sid       = "PublicList"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.backups.arn
      }
    ]
  })
}
