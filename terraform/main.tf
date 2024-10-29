provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

resource "aws_sagemaker_notebook_instance" "sagemaker_instance" {
  notebook_instance_name = var.instance_name
  instance_type          = var.instance_type
  role_arn               = aws_iam_role.sagemaker_role.arn
  subnet_id              = var.subnet_id
  lifecycle_config_name  = aws_sagemaker_notebook_instance_lifecycle_configuration.lc_config.name
  direct_internet_access = "Enabled"
}

resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "lc_config" {
  name = "${var.instance_name}-lifecycle-config"

  on_create = filebase64("${path.module}/scripts/on-create.sh")
  on_start  = filebase64("${path.module}/scripts/on-start.sh")
}

resource "aws_iam_role" "sagemaker_role" {
  name = "sagemaker-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "sagemaker.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
