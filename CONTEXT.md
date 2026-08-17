# SSD Monitor Domain

Single-context domain model for the SSD Monitor macOS application, providing hardware telemetry, volume status monitoring, and safe ejection capabilities for external drives.

## Language

**Target Volume**:
The external SSD storage volume monitored by the application for health, usage, and processes.
_Avoid_: External drive, USB stick, local disk

**Telemetry**:
Hardware health and operational metrics collected via S.M.A.R.T. sensors (e.g. temperature, overall health pass/fail status).
_Avoid_: System logs, statistics, benchmark

**Blocking Process**:
An operating system process holding active open file descriptors on the Target Volume, preventing safe ejection.
_Avoid_: Active app, background task, open program

**Safe Ejection**:
The graceful unmounting and detaching of the Target Volume from the operating system to prevent data loss or file corruption.
_Avoid_: Forced unmount, unplugging, disconnecting
