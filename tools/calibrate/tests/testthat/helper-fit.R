# Assemble a minimal valid FIT byte stream in memory for read_power_raw tests.
# recs: list of records list(ts=, pw=, dev=<# extra developer bytes>).
# dev>0 emits a definition with the developer-field bit (0x20) so the decoder
# must skip `dev` bytes per record by size.
make_fit <- function(recs, dev = 0L, invalid_pw = 65535L) {
  u16 <- function(v) c(bitwAnd(v, 0xFF), bitwAnd(bitwShiftR(v, 8), 0xFF))
  u32 <- function(v) c(bitwAnd(v, 0xFF), bitwAnd(bitwShiftR(v, 8), 0xFF),
                       bitwAnd(bitwShiftR(v, 16), 0xFF), bitwAnd(bitwShiftR(v, 24), 0xFF))
  # definition message (local type 0), global msg 20, fields 253(u32) + 7(u16)
  defhdr <- if (dev > 0) 0x60 else 0x40         # 0x20 = developer-field section present
  body <- c(defhdr, 0x00, 0x00, u16(20), 0x02,  # reserved, arch(LE), gnum=20, nfields=2
            253, 4, 0x86,                        # field 253 size4 uint32
            7,   2, 0x84)                         # field 7   size2 uint16
  if (dev > 0) body <- c(body, 0x01, 0x00, dev, 0x00)  # ndev=1: (devfnum=0,size=dev,idx=0)
  for (r in recs) {
    body <- c(body, 0x00, u32(r$ts), u16(r$pw))  # data msg, local type 0
    if (dev > 0) body <- c(body, rep(0xAB, dev)) # developer bytes (must be skipped)
  }
  data_size <- length(body)
  header <- c(14, 0x10, u16(100), u32(data_size), 0x2E, 0x46, 0x49, 0x54, 0x00, 0x00)
  all <- as.integer(c(header, body))
  path <- tempfile(fileext = ".fit")
  writeBin(as.raw(all), path)
  path
}
