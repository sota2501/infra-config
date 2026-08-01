# ssh_public_key を明示指定しなかった場合、github_username の公開鍵一覧
# (https://github.com/<user>.keys) を取得して使う。ローカルに鍵ファイルを
# 置く必要も ssh-agent から抜き出す必要もない。

data "http" "github_ssh_keys" {
  count = var.ssh_public_key == null && var.github_username != null ? 1 : 0
  url   = "https://github.com/${var.github_username}.keys"
}

locals {
  ssh_public_keys = (
    var.ssh_public_key != null
    ? [var.ssh_public_key]
    : [for line in split("\n", data.http.github_ssh_keys[0].response_body) : trimspace(line) if trimspace(line) != ""]
  )
}
