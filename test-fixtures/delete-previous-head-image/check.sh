#!/usr/bin/env bash
# Registry checks for caller-delete-previous-head-image.yaml.
#   check.sh snapshot <digest>   print every manifest digest that belongs to one image
#   check.sh gone <file>         fail unless every digest in <file> is gone
#   check.sh intact <tag>        fail unless <tag> pulls on both platforms and verifies
#   check.sh digest <ref>        print the digest <ref> points to
#   check.sh platform <tag> <arch>   print the linux/<arch> manifest digest of <tag>
#   check.sh shared <old> <platform> fail unless <old> and its signatures are gone while
#                                <platform> and its signatures remain and verify
set -euo pipefail

image="${IMAGE:?IMAGE is required, such as ghcr.io/<org>/<name>}"
repo="${image#ghcr.io/}"
accept="application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json"

registry_token() {
  curl -fsS -u "token:${GITHUB_TOKEN:?}" "https://ghcr.io/token?scope=repository:${repo}:pull" | jq -r .token
}
token="$(registry_token)"

# status <ref>: HTTP status of the manifest
status() {
  curl -sS -o /dev/null -w '%{http_code}' -I -H "Authorization: Bearer ${token}" -H "Accept: ${accept}" \
    "https://ghcr.io/v2/${repo}/manifests/$1"
}

# manifest <ref>: manifest body, empty when missing
manifest() {
  curl -fsS -H "Authorization: Bearer ${token}" -H "Accept: ${accept}" \
    "https://ghcr.io/v2/${repo}/manifests/$1" 2>/dev/null || true
}

# digest <ref>
digest() {
  curl -fsS -I -H "Authorization: Bearer ${token}" -H "Accept: ${accept}" \
    "https://ghcr.io/v2/${repo}/manifests/$1" | tr -d '\r' | awk 'tolower($1)=="docker-content-digest:"{print $2}'
}

snapshot() {
  local root="$1" subject referrers
  echo "${root}"
  local subjects=("${root}")
  while read -r child; do subjects+=("${child}"); echo "${child}"; done \
    < <(manifest "${root}" | jq -r '.manifests[]?.digest')
  for subject in "${subjects[@]}"; do
    referrers="${subject/:/-}"
    [[ "$(status "${referrers}")" == 200 ]] || continue
    digest "${referrers}"
    manifest "${referrers}" | jq -r '.manifests[]?.digest'
  done
}

gone() {
  local failed=0 count=0
  while read -r d; do
    count=$((count + 1))
    code="$(status "${d}")"
    if [[ "${code}" != 404 ]]; then
      echo "::error::${d} still exists (HTTP ${code})"
      failed=1
    fi
  done < "$1"
  [[ "${count}" -ge 4 ]] || { echo "::error::snapshot has only ${count} digests"; exit 1; }
  [[ "${failed}" == 0 ]] && echo "all ${count} versions of the previous head are gone"
  return "${failed}"
}

intact() {
  local tag="$1" d
  d="$(digest "${tag}")"
  [[ -n "${d}" ]] || { echo "::error::${image}:${tag} does not resolve"; exit 1; }
  for platform in linux/amd64 linux/arm64; do
    docker pull -q --platform "${platform}" "${image}:${tag}" >/dev/null
    echo "pulled ${image}:${tag} for ${platform}"
  done
  cosign verify "${image}@${d}" \
    --certificate-identity-regexp "${COSIGN_IDENTITY:?}" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null
  echo "cosign verify passed for ${image}:${tag} (${d})"
}

platform() {
  manifest "$1" | jq -r --arg arch "$2" \
    '.manifests[] | select(.platform.os == "linux" and .platform.architecture == $arch) | .digest'
}

shared() {
  local old="$1" platform="$2" failed=0 ref
  for ref in "${old}" "${old/:/-}"; do
    if [[ "$(status "${ref}")" != 404 ]]; then
      echo "::error::${ref} from the previous head still exists"
      failed=1
    fi
  done
  for ref in "${platform}" "${platform/:/-}"; do
    if [[ "$(status "${ref}")" != 200 ]]; then
      echo "::error::${ref}, shared with the release, is gone"
      failed=1
    fi
  done
  [[ "${failed}" == 0 ]] || return 1
  cosign verify "${image}@${platform}" \
    --certificate-identity-regexp "${COSIGN_IDENTITY:?}" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null
  echo "previous head and its signature are gone; shared ${platform} and its signature remain and verify"
}

case "${1:-}" in
  snapshot) snapshot "${2:?digest}" ;;
  gone) gone "${2:?file}" ;;
  intact) intact "${2:?tag}" ;;
  digest) digest "${2:?ref}" ;;
  platform) platform "${2:?tag}" "${3:?arch}" ;;
  shared) shared "${2:?old digest}" "${3:?platform digest}" ;;
  *) echo "usage: check.sh snapshot|gone|intact|digest|platform|shared <args>" >&2; exit 2 ;;
esac
