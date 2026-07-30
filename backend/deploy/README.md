# Deployment examples

These files are opt-in templates. They contain no SafeWalk production account,
registry, bucket, domain, or cluster identifiers.

- `oci-build.example.yaml` is an OCI DevOps build specification.
- `github-actions-oci.example.yml` is a manually dispatched deployment
  workflow. Copy it to `.github/workflows/` only after configuring a protected
  production environment and the referenced secrets and variables.

The manifests in `../k8s/` also use example image and domain values. Replace
`ghcr.io/your-org`, `safewalk.example.com`, and the certificate issuer email
before applying them.
