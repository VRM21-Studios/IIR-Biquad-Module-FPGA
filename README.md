# IIR Biquad (AXI-Stream) on FPGA

This repository provides a **reference RTL implementation** of a **second-order IIR biquad filter**, implemented in **Verilog** and integrated with **AXI-Stream** and **AXI-Lite**.

Target platform: **AMD Kria KV260**
Focus: **RTL architecture, fixed-point DSP decisions, and AXI correctness**

This is a true real-time streaming design; no frame buffering or offline-style processing is used.

---

## Motivation

This project was developed as part of a self-directed exploration of FPGA-based audio DSP and fixed-point recursive filtering. Biquad filters are widely used as practical second-order DSP building blocks, making them useful for studying the relationship between mathematical filter structures, numerical precision, and RTL implementation.

The project also explores how a parameterized recursive DSP structure can be integrated into a real-time streaming hardware environment.

---

## Overview

This module implements:

* **Function**: Second-order IIR biquad filtering (LPF / HPF / general biquad)
* **Data type**: Fixed-point **Q1.15** arithmetic
* **Scope**: Minimal, single-purpose DSP building block

The design is intentionally **not generic** and **not feature-rich**.
It exists to demonstrate *how the problem is solved in hardware*, not to provide a turnkey IP solution.

---

## Key Characteristics

* RTL written in synthesizable **Verilog**
* **AXI-Stream** data interface (stereo)
* **AXI-Lite** control interface for coefficients
* Explicit fixed-point arithmetic (bit-width fully defined)
* Deterministic, cycle-accurate behavior
* Designed and verified for real-time audio processing
* No software runtime or framework included

---

## Architecture

High-level structure:

```
AXI-Stream In
      |
      v
+------------------+
|  DSP Core        |
|  (IIR Biquad)    |
+------------------+
      |
      v
AXI-Stream Out
```

### Design Notes

* Processing is fully synchronous to a single clock
* No hidden state outside the RTL
* DSP core and AXI wrapper are explicitly separated
* All arithmetic decisions are documented

---

## Data Format

* **AXI-Stream width**: 32-bit
* **Fixed-point format**: Q1.15 (signed)

### Channel Layout

* `[31:16]` — Left channel
* `[15:0]`  — Right channel

Both channels share identical biquad coefficients.

---

## Latency

* **Fixed processing latency**: **1 clock cycle**

Latency is:

* deterministic
* independent of input signal characteristics

This behavior is intentional and suitable for streaming DSP pipelines.

---

## Verification & Validation

Verification was performed at two levels:

### 1. RTL Simulation

Dedicated testbenches verify:

* Functional correctness
* Fixed-point numerical behavior
* Saturation behavior
* AXI-Stream handshake correctness

Simulation results and plots are documented in:

```
results/README.md
```

### 2. Hardware Validation

The design was tested on real FPGA hardware:

* Tested on FPGA via **PYNQ overlay**
* PYNQ was used only as:

  * signal stimulus
  * observability tool

PYNQ software and bitstreams are **not part of this repository**.

---

## What This Repository Is

* A clean **RTL reference implementation**
* A demonstration of:

  * DSP reasoning
  * fixed-point trade-offs
  * AXI integration
* A building block for larger FPGA audio systems

---

## What This Repository Is Not

* ❌ A complete audio system
* ❌ A reusable DSP framework
* ❌ A parameter-heavy generic IP core
* ❌ A software-driven demo

The scope is intentionally constrained.

---

## Design Rationale (Summary)

Key design decisions include:

* Explicit fixed-point arithmetic for predictability
* Separation of DSP core and AXI wrapper
* Fixed latency for deterministic system integration
* Omission of advanced features to preserve clarity

These decisions reflect **engineering trade-offs**, not missing features.

Detailed rationale is documented in:

```
docs/design_rationale.md
```

---

## Project Status

This repository is considered **complete**.

* RTL is stable
* Simulation and hardware testing have been performed
* No further feature development is planned

The design is published as a **reference implementation**.

---

## License

Licensed under the **MIT License**.
Provided *as-is*, without warranty.

---

## Special Thanks


Special thanks to @imhaealf (https://github.com/imhaealf) for the technical collaboration and for contributing algorithmic and architectural ideas that influenced the design and development of this project.

---

## Additional Notes

> **This repository demonstrates design decisions, not design possibilities.**
