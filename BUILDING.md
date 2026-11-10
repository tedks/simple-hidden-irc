# Portable configuration check

The Bazel test parses the checked-in Tor and ngIRCd configuration without starting either service.

```bash
nix develop --command bazel test //:configuration_test
```

The pinned Nix shell supplies Bazel, Tor and ngIRCd; a bare Bazel run can select other binaries from `PATH` and is not the documented gate. The test action has no network access. It copies both configs into Bazel scratch space and replaces the container's Tor state directories with private scratch directories before `tor --verify-config`; it then runs ngIRCd's config-test mode and rejects diagnostics beyond the two known MOTD/admin-info warnings. Initial Nix and Bazel dependency fetches may need network. The Docker image uses Debian's older Tor/ngIRCd versions, so this check does not replace validating an actual image before deployment. This test does not build or start the Docker image, generate hidden-service keys, bind ports, or publish an onion address. The Dockerfile and entrypoint remain the manual runtime path.
