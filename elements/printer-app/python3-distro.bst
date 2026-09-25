kind: manual
description: Provide HPLIP's Python distribution detection without a runtime package manager.

sources:
  - kind: tar
    url: pypi:fc/f8/98eea607f65de6527f8a2e8885fc8015d3e6f5775df186e443e0964a11c3/distro-1.9.0.tar.gz
    ref: 2fa77c6fd8940f116ee1d6b94a2f90b13b5ea8d019b98bc8bafdcabcdd9bdbed

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-python-setuptools.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst

config:
  build-commands:
    - python3 -m build --no-isolation --wheel --outdir dist .
  install-commands:
    - python3 -m installer dist/*.whl --destdir "%{install-root}"
