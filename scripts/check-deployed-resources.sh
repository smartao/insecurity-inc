#!/usr/bin/env bash
# Verifica se algum capítulo (NN-nome/) tem recursos aplicados (state local
# terraform.tfstate != vazio), para evitar esquecer um `terraform destroy`
# pendente. Cada capítulo é independente e usa state local (sem backend S3).
#
# Uso:
#   ./scripts/check-deployed-resources.sh                    # notifica só se houver recursos
#   ./scripts/check-deployed-resources.sh --always            # notifica mesmo se estiver tudo limpo
#   ./scripts/check-deployed-resources.sh --no-notify          # só imprime no terminal, nunca notifica
#   ./scripts/check-deployed-resources.sh --quiet               # só imprime no terminal se houver recursos; se estiver limpo, não imprime nada
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALWAYS_NOTIFY=false
NO_NOTIFY=false
QUIET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --always) ALWAYS_NOTIFY=true; shift ;;
        --no-notify) NO_NOTIFY=true; shift ;;
        --quiet) QUIET=true; shift ;;
        *) echo "Argumento desconhecido: $1" >&2; exit 1 ;;
    esac
done

command -v jq >/dev/null || { echo "jq não encontrado no PATH." >&2; exit 1; }

declare -a DIRTY_LABS=()
declare -A LAB_DETAILS=()

for lab_dir in "$REPO_ROOT"/[0-9][0-9]-*/; do
    lab="$(basename "$lab_dir")"
    state_file="$lab_dir/terraform.tfstate"

    if [[ ! -f "$state_file" ]]; then
        $QUIET || echo "[$lab] sem state local (nunca aplicado?)."
        continue
    fi

    count="$(jq '.resources | length' "$state_file")"
    if [[ "$count" -gt 0 ]]; then
        DIRTY_LABS+=("$lab")
        summary="$(jq -r '.resources[] | "\(.type).\(.name)"' "$state_file" | sort -u | head -10 | paste -sd, -)"
        LAB_DETAILS["$lab"]="$count recurso(s): $summary"
        echo "$lab: on"
    else
        $QUIET || echo "[$lab] limpo (0 recursos no state)."
    fi
done

if [[ ${#DIRTY_LABS[@]} -gt 0 ]]; then
    body="$(for lab in "${DIRTY_LABS[@]}"; do echo "• $lab: ${LAB_DETAILS[$lab]}"; done)"
    if ! $NO_NOTIFY; then
        notify-send -u critical -i dialog-warning \
            "⚠ Terraform: recursos AWS ainda de pé" \
            "$body"
    fi
    exit 2
else
    $QUIET || echo "Nenhum recurso aplicado encontrado em nenhum capítulo."
    if $ALWAYS_NOTIFY && ! $NO_NOTIFY; then
        notify-send -u low "Terraform check" "Tudo limpo — nenhum recurso AWS aplicado."
    fi
fi
