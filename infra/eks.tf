locals {
  admin_entries = {
    for i, arn in var.admin_principal_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  github_entry = {
    github_pipeline = {
      principal_arn = aws_iam_role.github_pipeline.arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.cluster_name
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # nodes live in private subnets

  # Public API endpoint so GitHub-hosted runners and your laptop can run kubectl.
  cluster_endpoint_public_access = true

  # Admins are explicit. Using "creator admin" would flip between your laptop and the
  # pipeline role depending on who ran apply, and collide with the pipeline's access entry.
  enable_cluster_creator_admin_permissions = false

  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  access_entries = merge(local.github_entry, local.admin_entries)

  eks_managed_node_groups = {
    default = {
      instance_types = [var.eks_node_instance_type]
      min_size       = 2
      max_size       = 3
      desired_size   = 2
    }
  }
}

module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name                              = "${var.project}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lb_controller_irsa.iam_role_arn
  }

  depends_on = [module.eks]
}

resource "aws_ecr_repository" "app" {
  name                 = "${var.project}-todo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration { scan_on_push = true }
}

# --- Kubernetes objects Terraform owns (secret, SA, admin binding) ------------
resource "kubernetes_namespace_v1" "app" {
  metadata { name = "todo" }
  depends_on = [module.eks]
}

resource "kubernetes_secret_v1" "mongo" {
  metadata {
    name      = "mongo-credentials"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data = {
    MONGODB_URI = "mongodb://${local.mongo_app_user}:${random_password.mongo_app.result}@${aws_instance.mongo.private_ip}:27017/todos?authSource=admin"
    SECRET_KEY  = random_password.app_secret.result
  }
}

resource "kubernetes_service_account_v1" "app" {
  metadata {
    name      = "todo-app"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
}

# INTENTIONAL WEAKNESS: app pod runs with cluster-admin
resource "kubernetes_cluster_role_binding_v1" "app_admin" {
  metadata { name = "todo-app-cluster-admin" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.app.metadata[0].name
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
}
