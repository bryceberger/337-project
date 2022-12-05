typedef enum logic [1:0] {
    IDLE   = 'b00,
    BUSY   = 'b01,
    NONSEQ = 'b10,
    SEQ    = 'b11
} htrans_e;

typedef enum logic [3:0] {
    OUT   = 'b0001,
    IN    = 'b1001,
    DATA0 = 'b0011,
    DATA1 = 'b1011,
    ACK   = 'b0010,
    NACK  = 'b1010,
    STALL = 'b1110
} pid_e;
