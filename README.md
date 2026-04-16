# APB-Controlled I2C Master Controller with Clock Stretching Verification

## Overview

This project implements and verifies an **APB-controlled I2C Master Controller** using Verilog/SystemVerilog.  
The design supports register-based I2C write/read transactions, repeated START, ACK/NACK handling, programmable SCL generation, open-drain SDA/SCL behavior, APB register control, and clock-stretching tolerance.

The project was verified using **SystemVerilog testbenches** in **Vivado XSIM**, including I2C slave BFMs for normal transactions, NACK scenarios, and clock-stretching behavior.

---

## Key Features

- APB-controlled I2C master operation
- Register-based I2C write transaction
- Register-based I2C read transaction
- 2-byte read sequence
- Repeated START support
- ACK/NACK detection
- Wrong slave-address NACK handling
- Programmable SCL timing using clock divider
- Open-drain SDA/SCL pad-control modeling
- Clock-stretching tolerance
- Sticky status behavior through APB status register
- SystemVerilog testbench-based verification

---

## Block-Level Architecture

```text
APB Master/Testbench
        |
        v
+----------------+
|  APB Wrapper   |
+----------------+
        |
        v
+----------------------+
|   I2C Master Top     |
+----------------------+
        |
        +--> Transaction FSM
        |
        +--> Byte Engine
        |
        +--> Bit Engine
        |
        +--> Condition Generator
        |
        +--> Clock Divider
        |
        +--> Pad Controller
                    |
                    v
              SDA/SCL Bus
                    |
                    v
              I2C Slave BFM
```

---

## RTL Modules

| Module | Purpose |
|---|---|
| `apb_i2c_top.v` | Top-level APB-to-I2C integration |
| `apb_wrapper.v` | APB register interface and command/status control |
| `i2c_master_top.v` | Integrates I2C transaction blocks |
| `i2c_transaction_fsm.v` / `i2c_MASTER_FSM.v` | Controls I2C transaction sequence |
| `i2c_byte_engine.v` | Handles byte-level TX/RX and ACK/NACK sequencing |
| `i2c_bit_engine.v` | Handles bit-level SDA drive/sample timing |
| `i2c_cond_gen.v` | Generates START, repeated START, and STOP conditions |
| `i2c_clk_div.v` | Generates SCL phase/timing and supports clock stretching |
| `i2c_pad_ctrl.v` | Models open-drain SDA/SCL pad behavior |

---

## Verified Test Scenarios

| Test | Description | Result |
|---|---|---|
| Normal Write | Write `0x3C` to slave `0x48`, register `0x10` | PASS |
| Normal Read | Read two bytes from slave `0x48`, register `0x20` | PASS |
| Normal NACK | Wrong slave address produces NACK error | PASS |
| Clock-Stretch Write | Write transaction while slave stretches SCL | PASS |
| Clock-Stretch Read | 2-byte read while slave stretches SCL | PASS |
| Clock-Stretch NACK | Wrong-address NACK while SCL stretching is active | PASS |
| APB Write Trigger | APB programmed write command | PASS |
| APB Read Trigger | APB programmed read command | PASS |
| Status Read/Clear | APB status done/NACK/sticky clear behavior | PASS |

---

## Simulation Environment

- Simulator: **Vivado XSIM**
- HDL: **Verilog/SystemVerilog**
- Verification style: Directed SystemVerilog testbenches
- Debug method: Waveform analysis and `$display` transaction tracing

---

## Example Simulation Commands

In Vivado TCL console:

```tcl
restart
run -all
```

or:

```tcl
restart
run all
```

> Note: Vivado TCL commands are case-sensitive. Use `run -all` or `run all`, not `RUN -ALL`.

---

## Expected Key Test Outputs

### Normal Write

```text
[TB] WRITE_ONLY: WRITE 0x3C to reg 0x10
[TB][PASS] WRITE_ONLY mem[0x10]=0x3c
```

### Normal Read

```text
[TB] TEST2_ONLY: READ 2 bytes from reg 0x20
[TB] rd_byte_valid ... rd_byte = 0xa5
[TB] rd_byte_valid ... rd_byte = 0x5a
[TB][PASS] TEST2_ONLY read bytes = 0xa5 0x5a
```

### Clock-Stretch Write

```text
[SLAVE] received addr byte = 0x90
[SLAVE] received reg byte  = 0x10
[SLAVE] received data byte = 0x3c
[TB][PASS] STRETCH WRITE mem[0x10]=0x3c
```

### Clock-Stretch Read

```text
[SLAVE] received addr-W byte = 0x90
[SLAVE] received reg byte    = 0x20
[SLAVE] received addr-R byte = 0x91
[TB] rd_byte_valid ... rd_byte=0xa5
[TB] rd_byte_valid ... rd_byte=0x5a
[TB][PASS] STRETCH READ got 0xa5 0x5a
```

---

## Important Design Notes

### Open-Drain Behavior

I2C SDA and SCL are open-drain lines. The master or slave can only pull the bus low. A released line is pulled high.

In the testbench, this is modeled as:

```systemverilog
assign sda_bus = (sda_padoen_o || slave_sda_drive_low) ? 1'b0 : 1'b1;
assign scl_bus = (scl_padoen_o || slave_scl_drive_low) ? 1'b0 : 1'b1;
```

### Clock Stretching

Clock stretching occurs when the master releases SCL high, but the slave keeps SCL low.  
The master must wait until actual synchronized `scl_in` becomes high before sampling SDA or advancing the transaction.

Correct behavior:

```text
SCL low -> slave holds low -> master releases SCL -> bus remains low -> slave releases -> SCL rises -> master continues
```

---

## What Was Not Claimed

This project does **not** claim support for:

- Multi-master arbitration
- 10-bit I2C addressing
- High-speed I2C mode
- Formal verification
- UVM environment
- FPGA board-level validation
- DMA support

---

## Future Improvements

- Add constrained-random verification
- Add SystemVerilog Assertions for protocol checks
- Add functional coverage
- Add APB protocol assertions
- Add support for 10-bit I2C addressing
- Add multi-byte write FIFO support
- Add interrupt output for done/error events
- Port verification to UVM
