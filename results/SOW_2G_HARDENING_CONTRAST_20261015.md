# Task 2g — Hardened versus baseline update demonstration

**Question answered:** What evidence shows that the proposed update hardening changes outcomes, and can the difference be demonstrated?
**Disposition:** A reproducible host-only A/B demonstration now runs the same four update conditions through a deliberately unsafe baseline and the existing signed inactive-slot A/B reference. All four control checks pass.

## What was demonstrated

Run from the repository root:

```sh
python3 linux/appliance/hardening_contrast_demo.py
python3 -m unittest discover -s tests -p 'test_task2g_hardening_contrast.py' -v
python3 -m unittest discover -s tests -p 'test_task2g_ab_update.py' -v
```

| Scenario | Deliberately unsafe baseline | Hardened A/B reference | Evidence check |
|---|---|---|---|
| Valid signed release | Accepts the image in place | Verifies and stages to inactive B for trial boot | Both accept |
| Tampered release | Accepts altered bytes | Rejects signature before slot/state change; A remains active | Both expected outcomes observed |
| Interrupted update | Partial write damages active A | Partial inactive-slot write is not published; A remains active | Both expected outcomes observed |
| Failed trial health | Bad image remains active | Clears pending trial; confirmed A remains selected | Both expected outcomes observed |

The demo creates its keys, image, state, and slot files inside a temporary directory. It invokes the actual `ab_update_prototype.py` for the hardened cases. The baseline is a small, intentionally unsafe in-memory model; it is not a deployable updater. It has no device path or block-device operation.

## How this supports a hardening claim

Hardening is supported by observed control behavior against defined fault cases, not by the name of the design or by a device-tree node appearing. For the updater model, the acceptance criteria are: valid signed content can be staged; modified content is rejected before publication; interruption cannot replace the confirmed slot; and failed trial health returns selection to the confirmed slot. The contrast demo checks those conditions and the pre-existing A/B test suite separately checks the underlying update operations, boot-attempt limit, confirmation, and failure behavior.

The evidence shows that these controls work in the host reference model. It does **not** establish that the ZCU102 boot chain enforces authenticated boot, that the update state is power-loss-safe on SD/eMMC, or that a hardware-rooted key is provisioned. The model uses test-generated RSA keys and JSON state. Task 2g remains partial until the controls are integrated with U-Boot and a target image, authenticated through the actual boot chain, and fault-tested on the board. Task 2d remains an architecture/design result.

## Reproducibility record

- Program: `linux/appliance/hardening_contrast_demo.py`
- Contrast test: `tests/test_task2g_hardening_contrast.py`
- Underlying A/B tests: `tests/test_task2g_ab_update.py`
- Captured run: `results/task2g_hardening_contrast_20261015/demo_run.log`
- Hash manifest: `results/task2g_hardening_contrast_20261015/SHA256SUMS`
- Cumulative presentation: `deliverables/MSU2_Task2_Evidence_Review_20261015_v14.pptx`

On-target proof still needs (1) a documented verified-boot configuration and trust anchor, (2) authentic versus altered boot-image tests, (3) A/B installation and rollback through the real bootloader, and (4) reset/power-interruption fault tests with recovery evidence. Do not burn ZynqMP eFUSEs as part of this demonstration.
