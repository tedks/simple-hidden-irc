# Portable configuration check

The Bazel test parses the checked-in Tor and ngIRCd configuration without starting either service.

```bash
nix develop --command bazel test //:configuration_test
```

The pinned Nix shell supplies Bazel, Tor and ngIRCd. The test action has no network access. It copies both configs into Bazel scratch space and replaces the container's Tor state directories with private scratch directories before `tor --verify-config`; it then runs ngIRCd's config-test mode. Initial Nix and Bazel dependency fetches may need network. This test does not build or start the Docker image, generate hidden-service keys, bind ports, or publish an onion address. The Dockerfile and entrypoint remain the manual runtime path.
