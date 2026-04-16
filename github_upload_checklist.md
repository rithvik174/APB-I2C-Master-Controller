# GitHub Upload Checklist

## Repository Name

Recommended:

```text
APB-I2C-Master-Controller
```

or:

```text
APB-Controlled-I2C-Master
```

Avoid spaces and very long names.

---

## Before Upload

- [ ] Remove duplicate old RTL versions
- [ ] Keep final module names stable:
  - `i2c_master_top`
  - `i2c_clk_div`
  - `i2c_bit_engine`
  - `i2c_cond_gen`
- [ ] Keep only final passing testbenches
- [ ] Remove temporary debug-only files unless useful
- [ ] Add waveform screenshots to `waveforms/screenshots/`
- [ ] Add README
- [ ] Add documentation folder
- [ ] Add test result logs
- [ ] Add `.gitignore`

---

## Suggested Folder Structure

```text
APB-I2C-Master-Controller/
├── README.md
├── rtl/
├── tb/
├── docs/
├── waveforms/
│   └── screenshots/
└── sim_logs/
```

---

## Suggested Commit Message

```text
Initial commit: APB-controlled I2C master with verification environment
```

---

## Suggested Repository Description

```text
Verilog/SystemVerilog APB-controlled I2C master verified for write/read, ACK/NACK, repeated START, APB status, and clock-stretch scenarios.
```
