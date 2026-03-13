# Deployments

## Ambiente: `llm-hub`

Resource Group: `llm-hub`
Região: `West US 3`
Subscription: `07042b31-10ca-483d-9df2-f7b8fb78335c`

---

## Deploy Ativo — `tq2trlw3xf4io`

| Recurso | Nome |
|---|---|
| Container App | `ca-litellm-tq2trlw3xf4io` |
| Container Apps Environment | `cae-litellm-tq2trlw3xf4io` |
| Container Registry | `crtq2trlw3xf4io` |
| Log Analytics | `log-litellm-tq2trlw3xf4io` |
| Application Insights | `appi-litellm-tq2trlw3xf4io` |
| Managed Identity | `id-ca-litellm-tq2trlw3xf4io` |

**URL:** `https://ca-litellm-tq2trlw3xf4io.kindbush-7e3bda80.westus3.azurecontainerapps.io`
**Replicas:** min 2 / max 3
**Banco de dados:** `psql-litellm-sxyzumqumltie.postgres.database.azure.com`

### Observações
- Master key é a mesma do deploy antigo
- **Salt key diferente do deploy antigo** — impede leitura das credenciais criptografadas no banco
- Para corrigir: `azd env set LITELLM_SALT_KEY <salt-key-do-deploy-antigo>` + `azd provision`

---

## Deploy Antigo — `sxyzumqumltie`

| Recurso | Nome |
|---|---|
| Container App | `ca-litellm-sxyzumqumltie` |
| Container Apps Environment | `cae-litellm-sxyzumqumltie` |
| Container Registry | `crsxyzumqumltie` |
| Log Analytics | `log-litellm-sxyzumqumltie` |
| Application Insights | `appi-litellm-sxyzumqumltie` |
| Managed Identity | `id-ca-litellm-sxyzumqumltie` |

**URL:** `https://ca-litellm-sxyzumqumltie.kindbush-7e3bda80.westus3.azurecontainerapps.io`
**Banco de dados:** `psql-litellm-sxyzumqumltie.postgres.database.azure.com` (compartilhado)

### Observações
- Deploy funcional com 25 endpoints healthy e 4 unhealthy
- Unhealthy: 2 modelos Azure fine-tuned com nome truncado no banco, 2 modelos Vercel v0 que exigem plano Premium
- Pode ser removido após corrigir o salt key no deploy novo e validar funcionamento

---

## Banco de Dados (compartilhado)

| Campo | Valor |
|---|---|
| Host | `psql-litellm-sxyzumqumltie.postgres.database.azure.com` |
| Porta | `5432` |
| Database | `litellmdb` |

> O banco é compartilhado entre os dois deploys. Toda configuração de modelos, chaves e teams é comum.

---

## Pendências

- [ ] Corrigir salt key no deploy novo (`tq2trlw3xf4io`) para usar o mesmo do deploy antigo
- [ ] Configurar domínio customizado `ai.miia.tech` apontando para o deploy novo
- [ ] Corrigir nome dos 2 modelos Azure fine-tuned com nome truncado no banco
- [ ] Avaliar remoção do deploy antigo (`sxyzumqumltie`) após validação
