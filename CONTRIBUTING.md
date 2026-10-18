# Contributing

Thanks for helping make headless QNX development easier.

Before opening a pull request:

1. Run `sh scripts/verify.sh`.
2. Test changes on QNX 8.0 and record the target image, hardware, and commands.
3. Keep provider-specific examples separate from the core relay protocol.
4. Do not commit generated bundles, private keys, Wi-Fi credentials, service
   variables, or device logs.
5. Include the exact behavior you verified in the pull request test plan.

A useful bug report includes the QNX version, Raspberry Pi model, whether
`bcm0` is in the default or `/wifi` stack, the hosting provider, and a redacted
tail of `qnx-onboot.log` and `qnx-tunnel.log`.

The project uses the Apache License 2.0. By contributing, you agree that your
contribution is provided under that license.
