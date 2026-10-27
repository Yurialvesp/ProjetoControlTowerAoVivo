#!/usr/bin/env bash
set -euo pipefail

PERFIL="${1:-DEFAULT}"
APP_NAME="${2:-minha-torre}"
CATALOG="lakehouse_vertice"
WAREHOUSE_ID="d04c9f02eff32f93"

echo "Buscando service_principal_client_id do app '$APP_NAME' (perfil: $PERFIL)..."
SP_CLIENT_ID=$(databricks apps get "$APP_NAME" --profile "$PERFIL" -o json | node -e "const d = JSON.parse(require('fs').readFileSync(0, 'utf8')); console.log(d.service_principal_client_id || '');")

if [ -z "$SP_CLIENT_ID" ]; then
  echo "Erro: não foi possível obter service_principal_client_id para '$APP_NAME'." >&2
  exit 1
fi

echo "Service Principal Client ID: $SP_CLIENT_ID"
echo "Concedendo permissões no catálogo '$CATALOG' (schemas gold e silver)..."

databricks experimental aitools tools query \
  --warehouse "$WAREHOUSE_ID" \
  --profile "$PERFIL" \
  --output json \
  "GRANT USE CATALOG ON CATALOG ${CATALOG} TO \`${SP_CLIENT_ID}\`" \
  "GRANT USE SCHEMA, SELECT ON SCHEMA ${CATALOG}.gold TO \`${SP_CLIENT_ID}\`" \
  "GRANT USE SCHEMA, SELECT ON SCHEMA ${CATALOG}.silver TO \`${SP_CLIENT_ID}\`"

echo "Permissões concedidas com sucesso para $SP_CLIENT_ID."
