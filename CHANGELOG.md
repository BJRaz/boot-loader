## [0.2.2] 2026-04-19
### Added
 - PCB-based context switching in `boot2.asm` with manual process table layout (no NASM `struc`), per-process stacks, and round-robin process selection.
 - `printf` support for `%d` (unsigned decimal) and `\n` escape sequence.

### Changed
 - Timer scheduling flow now switches from a direct INT 0x1c approach to a direct IRQ0 (`INT 0x08`) hook.
 - Process execution model updated so each process prints once per time-slice and is reloaded at entry (`IP`/`SP`) on switch-in.
 - Stage-1 loader read window increased to `SECTORS_TO_READ equ 4` to safely load current `boot2.bin` size growth.

### Fixed
 - Restored proper PIC behavior by issuing EOI from the `INT 0x08` timer handler.
 - Fixed `printf` `%x` formatting bugs (indexing/clobber issues in hex rendering path).
 - Fixed argument-width mismatch for `procedure` (`db` -> `dw`) causing corrupted formatted output.

### Refactored
 - Reduced dead/unused data in `boot2.asm` and cleaned control-flow nits (duplicate jump/redundant jump removal), shrinking stage-2 binary footprint.
 - Updated `.github/copilot-instructions.md` to reflect current architecture, sector-read caveat, and ISR/output constraints.

### [0.1.3] 2019-10-31 
### Added
 - custom interrupt handler implemented, called when executing 'int 0x80' 
## [0.1.2] 2019-10-9 
### Added
 - boot2.asm, added this asm file for prototyping. Updated Makefile accordingly.
 - left- and right arrow key handling (prototyping) 
### Changed
 - backspace handling changed
### Removed
 - Diskoperations removed temporarely

## [0.1.1] 2019-05-19 
### Added
 - proptyped reset, and read from floppydrive to a specific memory location

## [0.1.0] 2019-05-03
### Added
 - initial commits
 - prototyped a boot-loader

