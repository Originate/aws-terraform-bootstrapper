resource "aws_iam_policy" "terraform" {
  name = "terraform-backend"
  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:ListBucket"
          ]
          Resource = [
            module.backend.bucket_arn
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "s3:*Object"
          ]
          Resource = [
            "${module.backend.bucket_arn}/*"
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "kms:DescribeKey",
            "kms:GenerateDataKey",
            "kms:Decrypt"
          ]
          Resource = [
            module.backend.kms_key_arn
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:DeleteItem"
          ]
          Resource = [
            module.backend.dynamodb_table_arn
          ]
        }
      ]
    }
  )
}
