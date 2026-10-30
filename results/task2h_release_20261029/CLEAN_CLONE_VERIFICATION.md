# Remote recovery check — October 30, 2026

Fetched a fresh shallow sparse clone directly from GitHub branch
feature/ratio2-j55-rebuild at 425cb9267280b3ca1cd223054d569f38f81e8f21.
Only the documented dependency directories were checked out. No original
bare_metal/vitis workspace or scratchpad paths were used by the build.

- All 211 SHA256 manifest entries passed using the files fetched from GitHub.
- Clone git status was clean before and after the out-of-tree build.
- Final application compiled with the documented script and AMD PetaLinux
  2025.1 GCC 13.3.0. Entry: 0x00100940.
- Packaged October 29 final ELF hash:
  e8e290945a304a9c4ed15ec90a47c2d44dcb9cf9d25b01256dc3b97e6009a25b
- Fresh clone full ELF hash:
  88431cbc59eced0d955fe85e1ba56dc6cbf634561d5a9613d0e702ebdb93e4a8
- The original checkout build reproduced the packaged full ELF hash exactly.
  The relocated clone differs in debug path metadata and GNU build ID.
- Raw binary comparison found exactly 20 changed bytes, all inside the
  .note.gnu.build-id descriptor at address 0x11311c. After excluding that
  section with objcopy, the binary images matched byte-for-byte.

This establishes a successful build from remotely available committed
inputs, plus matching executable/data content apart from the build ID.
It does not claim full-ELF bit reproducibility across checkout paths or
new hardware validation. No board or SD was modified.

The original Morgan checkout remains dirty because unrelated pre-existing
changes and untracked files were preserved. The release files are committed.
