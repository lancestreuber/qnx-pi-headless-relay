# Custom Target Image integration

QNX Custom Target Images are the maintainable route for shipping this service.
The CTI build already has a supported `post_start` snippet type for commands
that run from `/etc/startup/post_startup.sh`, plus `system_files` snippets for
adding files to the system partition.

Official references:

- [CTI getting started](https://qnx.com/developers/docs/qnxeverywhere/com.qnx.doc.target_images/topic/cti/getting_started.html)
- [CTI customization](https://qnx.com/developers/docs/qnxeverywhere/com.qnx.doc.target_images/topic/cti/customization.html)
- [CTI snippets](https://qnx.com/developers/docs/qnxeverywhere/com.qnx.doc.target_images/topic/cti/snippets.html)

## Apply the draft overlay

Clone QNX's CTI repository, then run:

```sh
cti/install-overlay.sh /path/to/custom-target-image-builds
```

The overlay installs four files under
`system/usr/lib/qnx-headless-connect/` and adds two snippets:

- `system_files.custom.qnx_headless_connect` includes the files in the system
  partition.
- `post_start.~85.qnx_headless_connect` starts the supervisor after normal
  networking setup, but only when `/boot/qnx-connect.conf` exists.

Build the Raspberry Pi 5 image using QNX's documented command:

```sh
make TARGET=rpi5
```

After flashing, use `scripts/configure.py` to generate the per-device material
and copy its `boot/` directory to the FAT partition. The system copy of the
scripts takes precedence automatically; the extra boot copies may be omitted
after CTI validation.

## Validation still required

This overlay matches the current CTI snippet contract, but it has not yet gone
through a clean CTI build. Before proposing it upstream:

1. Build an unmodified `rpi5` CTI image.
2. Apply the overlay and build again from a clean tree.
3. Confirm the four files and post-start command in the generated image.
4. Boot with no `qnx-connect.conf` and confirm behavior is unchanged.
5. Provision a test device and confirm automatic tunnel startup.
6. Restart the relay, reboot the QNX Pi, and run the idle-session test.

The overlay must stay opt-in. No keys, Wi-Fi settings, relay hostname, or
device identity belongs in a shared CTI image.
