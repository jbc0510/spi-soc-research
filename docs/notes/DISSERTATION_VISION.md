# Research Vision - PhD Dissertation

## Author: Jerry Conway (jbc0510)
## Program: PhD - Embedded Security

## Evolution of BASE Project
BASE v1.0 → Secure boot FSM (~200 cells)
BASE v2.0 → FSM + Wishbone bus (~835 cells)
BASE v3.0 → Full HSM SHA-256/AES-128/TRNG (29,037 cells)
BASE v4.0 → Post-quantum + TinyML (dissertation target)

## Dissertation Focus
"Post-Quantum Hardware Root of Trust with 
TinyML Anomaly Detection for Embedded Systems"

## Key Components
### 1. Post-Quantum Cryptography (Dilithium)
- Replace classical signatures with CRYSTALS-Dilithium
- NIST PQC standard - quantum resistant
- Implemented in silicon on SKY130 process

### 2. TinyML Anomaly Detection
- Replace rule-based tamper monitor
- Neural network learns normal behavior
- Detects novel/unknown attack patterns
- Runs on minimal hardware resources

### 3. Optimized Secure Communication (THIS RESEARCH)
- SPI performance characterization
- Bare-metal vs Linux overhead quantified
- Secure channel from HSM to host system
- Foundation for BASE v4.0 communication stack

## Connection to Current SPI Research
This task characterizes the communication layer
that BASE v4.0 will use to interface with host
systems. Performance data collected here directly
informs the BASE v4.0 architecture decisions.

## Milestones
- BASE v3.0 paper    ← READY NOW
- A Exam             ← next milestone
- SPI research       ← current work
- BASE v4.0 design   ← dissertation
- Tape-out BASE v4.0 ← final goal
