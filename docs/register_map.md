# Register map

Base address: assigned by the interconnect (the block occupies 16 bytes).
All registers are 32 bits, word-aligned, read/write, and reset to `0x00000000`.

| Offset | Name   | Access | Reset        | Purpose                        |
|-------:|--------|--------|--------------|--------------------------------|
| `0x00` | `CTRL` | R/W    | `0x00000000` | General-purpose control        |
| `0x04` | `CFG`  | R/W    | `0x00000000` | Configuration                  |
| `0x08` | `DATA` | R/W    | `0x00000000` | Data or command                |
| `0x0C` | `GP`   | R/W    | `0x00000000` | General-purpose data / status  |

The names describe intent only. In this version every register is plain
storage: no field has a hardware side effect, and hardware never writes to
them, so there is no update-priority question between software and logic. If
a peripheral later drives a status field, define its priority against software
writes here before changing the RTL.

## Bit fields

Each register is a single 32-bit field, `[31:0]`, read/write. There are no
reserved bits: all 32 bits store and return what was written.

## Access rules

- **Byte strobes.** Each `WSTRB` bit enables one byte lane; disabled lanes keep
  their value. `WSTRB = 0000` completes with `OKAY` and changes nothing.
- **Reads** have no side effects.
- **Invalid addresses.** Anything at or above `0x10`, or with the low two bits
  non-zero, returns `SLVERR`. Such a write modifies nothing; such a read
  returns `0`.
- **Same-cycle read and write to one register.** The read returns the old
  value.
- **Reset** (`aresetn` low, sampled on `aclk`) clears all four registers and
  drops any transaction in flight.
