# D-1 RESOLVED — PetaLinux 2025.1 at Morgan; and stile is on an unsupported host

Decided at LPS (stile), 2026-08-25. MSU-2 Task 2, IAC/TAT P1-22-2393.
Source: UG1144 PetaLinux Tools Documentation Reference Guide, v2025.1,
May 29 2025, Chapter 2 "Setting Up Your Environment", Installation Requirements.

## THE QUESTION

Morgan (`bxqp8b3-ub22`) has PetaLinux **2025.2**. stile (LPS) has **2025.1**.
Any SOW 2.g U-Boot rebuild happens on stile at 2025.1. A one-release SDK skew
undercuts the two-site reproduction claim, which is the point of the protocol.

D-1 asked: install 2025.1 alongside 2025.2 at Morgan, or keep 2025.2 and
characterise the skew? The stated prerequisite was to check UG1144 for whether
Ubuntu 22.04 is a supported host for 2025.1 BEFORE downloading.

## WHAT UG1144 v2025.1 SAYS

Supported operating systems for PetaLinux 2025.1:

- Ubuntu Desktop/Server **22.04.2, 22.04.3, 22.04.4, 22.04.5 LTS**
- OpenSuse Leap 15.4
- AlmaLinux 8.10, 9.4, 9.5
- CentOS and RHEL removed entirely, to align with upstream Yocto

**Ubuntu 24.04 does not appear in that list.**

Minimum workstation requirements, same section:

- 8 GB RAM
- 2 GHz CPU, minimum eight cores
- **100 GB free disk**

Also stated in the same chapter: PetaLinux 2025.1 works only with hardware
designs exported from Vivado Design Suite 2025.1.

## DECISION

**Install PetaLinux 2025.1 alongside 2025.2 at Morgan**, subject to the 100 GB
disk check below. Morgan runs Ubuntu 22.04.5, which is on the supported list.
Aligning both sites at 2025.1 restores the two-site reproduction claim for any
2.g U-Boot rebuild, and it does so on the sanctioned path.

NOT DECIDED: whether 2025.2 is removed from Morgan afterwards. Keeping both is
the default until something forces a choice.

### Gate before downloading

`df -h` at Morgan must show at least 100 GB free on the target filesystem.
This has NOT been measured; Morgan was not available when this was written.
Do not start the download before running it.

Both sites already have Vivado 2025.1, so the Vivado-version constraint is met.

## THE FINDING THAT CAME OUT OF THIS

**stile is Ubuntu 24.04.4. Ubuntu 24.04 is not a supported host for PetaLinux
2025.1. stile has been running an unsupported configuration.**

This is not a hypothetical: UG1144 v2025.1 acknowledges 24.04 is used in
practice by documenting a workaround for a `uid_map` error encountered when
building on it, namely writing 0 to
`/proc/sys/kernel/apparmor_restrict_unprivileged_users`, referencing an
upstream Yocto mailing list thread. So AMD knows people build there; they do
not support it.

**This inverts a framing carried all week.** stile was treated as the reference
site and Morgan as the skewed one. On host OS support the reverse is true:

| | stile | Morgan |
|---|---|---|
| OS | Ubuntu 24.04.4 | Ubuntu 22.04.5 |
| PetaLinux | 2025.1 | 2025.2 |
| UG1144 2025.1 host support | **NOT listed** | **supported** |

### NOT CLAIMED

- That anything built on stile is wrong. No defect has been attributed to the
  unsupported host. The `uid_map` error described in UG1144 has NOT been
  observed on stile, and no PetaLinux build was run on stile this session.
- That stile should be reimaged, or that 2.g rebuilds should move to Morgan.
  That is a larger question than D-1 asked. Raised, not decided.
- That UG1144 v2025.2 says the same thing. Only the v2025.1 document was read.
  If Morgan keeps 2025.2 as well, its host requirements are a separate check.

## CONSEQUENCE FOR SECTION 8.3

`SESSION_RECAP_20260820.md` 8.3 gates the 2.g watchdog remediation
(`CONFIG_WDT=y` + `CONFIG_WDT_CDNS=y`) on D-1, and describes the U-Boot rebuild
as "an LPS job (PetaLinux 2025.1 lives on stile)".

That is still true and still workable. But once 2025.1 exists at Morgan, the
rebuild could run at either site — and Morgan would be the one on a supported
host. Worth revisiting when the install is done, not before.

## SOW POSITION

D-1 is a prerequisite decision, not a SOW contractual activity. Nothing in
SOW 2.a-2.g advanced by this document. It unblocks 8.3, which is 2.g work.

## REPRODUCE

UG1144 v2025.1, Chapter 2, "Installation Steps" -> "Installation Requirements".
The document is dated May 29 2025. Read 2026-08-25.
