resource "aws_codecommit_repository" "chaos_gitops_repository" {
  repository_name = "chaos_gitops_repository"
  default_branch  = "main"
}

resource "aws_iam_user" "codecommit" {
  name = "${local.name}-codecommit"
}

resource "aws_iam_policy_attachment" "codecommit" {
  name       = "iam-codecommit"
  users      = ["${aws_iam_user.codecommit.name}"]
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeCommitPowerUser"
}

resource "aws_iam_service_specific_credential" "credentials" {
  service_name = "codecommit.amazonaws.com"
  user_name    = aws_iam_user.codecommit.name

  provisioner "local-exec" {
    command = <<-EOT
        cd ../../..
        function url_encode() {
            echo "$@" \
            | sed \
                -e 's/%/%25/g' \
                -e 's/ /%20/g' \
                -e 's/!/%21/g' \
                -e 's/"/%22/g' \
                -e "s/'/%27/g" \
                -e 's/#/%23/g' \
                -e 's/(/%28/g' \
                -e 's/)/%29/g' \
                -e 's/+/%2b/g' \
                -e 's/,/%2c/g' \
                -e 's/-/%2d/g' \
                -e 's/:/%3a/g' \
                -e 's/;/%3b/g' \
                -e 's/?/%3f/g' \
                -e 's/@/%40/g' \
                -e 's/\$/%24/g' \
                -e 's/\&/%26/g' \
                -e 's/\*/%2a/g' \
                -e 's/\./%2e/g' \
                -e 's/\//%2f/g' \
                -e 's/\[/%5b/g' \
                -e 's/\\/%5c/g' \
                -e 's/\]/%5d/g' \
                -e 's/\^/%5e/g' \
                -e 's/_/%5f/g' \
                -e 's/`/%60/g' \
                -e 's/{/%7b/g' \
                -e 's/|/%7c/g' \
                -e 's/}/%7d/g' \
                -e 's/~/%7e/g'
        }

        pw=$(url_encode ${self.service_password})
        git remote add codecommit https://${self.service_user_name}:$pw@git-codecommit.${local.amp_ws_region}.amazonaws.com/v1/repos/${aws_codecommit_repository.chaos_gitops_repository.repository_name} || true
    EOT 
  }
}
