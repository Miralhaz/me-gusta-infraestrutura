# =============================================================================
# SES - identidades de e-mail para o consumer de alertas
# =============================================================================
# O consumer pode enviar os alertas pelo SES (API, usando o LabInstanceProfile
# das instancias backend). Antes de enviar, a identidade do remetente precisa
# ser verificada. Enquanto a conta estiver no sandbox do SES, os destinatarios
# tambem precisam ser verificados.
#
# IMPORTANTE (AWS Academy): a role do laboratorio bloqueia as acoes de
# gerenciamento de identidade (ses:CreateEmailIdentity, GetEmailIdentity,
# ListEmailIdentities etc.). Por isso a criacao fica desligada por padrao
# (enable_ses_email_identity = false) e o consumer usa SMTP ou SNS. Em uma
# conta com permissao, defina true no terraform.tfvars e rode `tofu apply`.
#
# Sem tags de proposito: o provider envia tags dentro do proprio
# CreateEmailIdentity, e a role do Academy tambem nao permite ses:TagResource.
# =============================================================================

resource "aws_sesv2_email_identity" "alertas" {
  for_each       = var.enable_ses_email_identity ? var.ses_email_identities : toset([])
  email_identity = each.value
}
