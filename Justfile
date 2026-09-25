bst2_image := env("BST2_IMAGE", "registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:64eb0b4930d57a92710822898fb73af6cc1ae35d")
image_ref := "ghcr.io/projectbluefin/hplip-printer-app:build"

default:
    @just --list

bst *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "${HOME}/.cache/buildstream"
    podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{ justfile_directory() }}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -w /src \
        "{{ bst2_image }}" \
        bash -c 'bst "$@"' -- --no-interactive ${BST_FLAGS:-} {{ ARGS }}

validate:
    just bst show --deps all oci/hplip-printer-app.bst

fetch:
    just bst source fetch --ignore-project-source-remotes --source-remote https://cache.projectbluefin.io:11001 --deps all oci/hplip-printer-app.bst

build:
    just bst build oci/hplip-printer-app.bst
    just export

export:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf .build-out
    just bst artifact checkout oci/hplip-printer-app.bst --directory /src/.build-out
    image_id="$(podman pull -q oci:.build-out)"
    rm -rf .build-out
    podman tag "$image_id" "{{ image_ref }}"

verify:
    just validate
    just build
    tests/oci-appliance.sh
    just check-no-devel

# No devel content in the image (fsdk-containers printing-base consumer rule 5)
check-no-devel:
    #!/usr/bin/env bash
    set -euo pipefail
    IMAGE="{{ image_ref }}"
    root="$(mktemp -d)"
    ctr="$(podman create "${IMAGE}" /none)"
    trap 'podman rm -f "${ctr}" >/dev/null; chmod -R u+w "${root}"; rm -rf "${root}"' EXIT
    podman export "${ctr}" | tar -C "${root}" -xf -
    bad="$(cd "${root}" && find . -path ./usr/share/licenses -prune -o \( -path ./usr/include -o -name '*.a' -o -name '*.la' \
          -o -type d -name pkgconfig -o -type d -name cmake \) -print -quit)"
    [ -z "${bad}" ] || { echo "devel content in ${IMAGE}: ${bad}" >&2; exit 1; }
    echo "OK: no devel content in ${IMAGE}"

sbom:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "${HOME}/.cache/buildstream" "${HOME}/.cache/pip"
    revision="$(git rev-parse HEAD)"
    podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{ justfile_directory() }}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -v "${HOME}/.cache/pip:/root/.cache/pip:rw" \
        -w /src \
        -e REVISION="$revision" \
        "{{ bst2_image }}" \
        bash -c '
            pip install --quiet git+https://gitlab.com/BuildStream/buildstream-sbom.git@0706fec3bedf6f73bd9d2fed32c2aed585feef8d
            buildstream-sbom oci/hplip-printer-app.bst \
                --spdx-name hplip-printer-app \
                --spdx-namespace "https://github.com/projectbluefin/hplip-printer-app/sbom/${REVISION}" \
                --spdx-creator "Tool: buildstream-sbom" \
                --spdx-creator "Organization: projectbluefin" \
                --deps all \
                --output /src/hplip-printer-app.spdx.json
        '
