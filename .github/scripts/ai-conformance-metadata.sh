#!/usr/bin/env bash
# Derives submission directory and platform name from tenancy model.
# Usage: ai-conformance-metadata.sh <tenancy_model>
# Outputs: submission_dir and platform_name to $GITHUB_OUTPUT

set -euo pipefail

TENANCY_MODEL="${1:?Usage: ai-conformance-metadata.sh <tenancy_model>}"

case "${TENANCY_MODEL}" in
  private-nodes)
    SUBMISSION_DIR="vcluster-private-nodes"
    PLATFORM_NAME="vCluster with Private Nodes"
    ;;
  shared)
    SUBMISSION_DIR="vcluster"
    PLATFORM_NAME="vCluster"
    ;;
  standalone)
    SUBMISSION_DIR="vcluster-standalone"
    PLATFORM_NAME="vCluster Standalone"
    ;;
  *)
    echo "::error::Unknown tenancy model: ${TENANCY_MODEL}"
    exit 1
    ;;
esac

{
  echo "submission_dir=${SUBMISSION_DIR}"
  echo "platform_name=${PLATFORM_NAME}"
} >> "${GITHUB_OUTPUT}"

echo "Tenancy model: ${TENANCY_MODEL}"
echo "Submission dir: ${SUBMISSION_DIR}"
echo "Platform name: ${PLATFORM_NAME}"
