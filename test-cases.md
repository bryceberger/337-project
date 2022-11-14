# Data Buffer
Note, run each using AHB side and USB side inputs. Also check buffer occupancy after each read/write/flush operation.
- Write data
- Read back data
- Read when empty
- Write when full
- Write 64, then read
- Write, flush, read
- Push when full (should drop first element in queue?)

# AHB Lite Slave
- Reset, check for default values
- Write to each invalid address (3 cases)
- Write to read only
- Read default of every address
- Make sure at least one read and write of each size occurs, and at each misalignment (2 byte with high LSB, 4 byte with high LSB and 2 LSBs)
- Read and write without asserting select
- Write and read from zero address
- Read status, error, and occupancy registers (test each value separately)
- Write each value to packet control register
- Write and then read invalid value from packet control register (should not result in output on USB side)
- Write to packet control register and check that it clears at the right time
- Write to flush buffer register and check that it clears at the right time

# USB TX Module
- Reset, check for default values
- Send ACK, NAK, and STALL (should not care about data buffer)
- Send data, must validate sync, PID, data, and CRC
  - One byte
  - Zero bytes
  - 64 bytes
  - Data requiring bit stuffing (0xFFFF, 0b11110000, and CRC)

# USB RX Module
- Reset, check for default values
- Receive ACK, NAK, and STALL
- Receive OUT and IN (with CRC, check with matching/not matching address and endpoint number)
- Receive data, should validate CRC
  - One byte
  - Zero bytes
  - 64 bytes
  - Data with bit stuffing
- Receive data with bad sync
- Receive data with bad PID (invalid number and inverted version wrong)
- Receive data with bad CRC
- Receive data with bad/no EOP
- Handshake packet that has data
