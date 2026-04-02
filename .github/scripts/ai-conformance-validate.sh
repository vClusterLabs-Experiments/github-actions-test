#!/usr/bin/env bash
# Validates a PRODUCT.yaml against the upstream cncf/k8s-ai-conformance validator.
# Usage: ai-conformance-validate.sh <k8s_version> <submission_dir> <product_yaml_path>
# Writes validation output to ./output/validation-output.txt

set -euo pipefail

K8S_VERSION="${1:?Usage: ai-conformance-validate.sh <k8s_version> <submission_dir> <product_yaml>}"
SUBMISSION_DIR="${2:?Missing submission_dir}"
PRODUCT_YAML="${3:?Missing product_yaml path}"

# Strip 'v' prefix if present
K8S_VER="${K8S_VERSION#v}"

VALIDATOR_DIR="/tmp/k8s-ai-conformance-validator-$$"

echo "Validating PRODUCT.yaml for v${K8S_VER}/${SUBMISSION_DIR}"

# Clone upstream validator to a unique directory
git clone --depth=1 https://github.com/cncf/k8s-ai-conformance.git "${VALIDATOR_DIR}"

# Place PRODUCT.yaml in the expected directory structure
mkdir -p "${VALIDATOR_DIR}/v${K8S_VER}/${SUBMISSION_DIR}"
cp "${PRODUCT_YAML}" "${VALIDATOR_DIR}/v${K8S_VER}/${SUBMISSION_DIR}/PRODUCT.yaml"

# Run upstream validator
cd "${VALIDATOR_DIR}"
go run scripts/validate.go "v${K8S_VER}/${SUBMISSION_DIR}/PRODUCT.yaml" 2>&1 | tee "${GITHUB_WORKSPACE}/output/validation-output.txt"
