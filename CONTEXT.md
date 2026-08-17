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

**Dynamic Status Item Visibility**:
The conditional visibility of the NSStatusItem menu bar icon based on the mounting state of the Target Volume.
_Avoid_: Permanent icon, ghost icon, hidden window

**Background Volume Observer**:
The background daemon thread listening for operating system volume mount and unmount events.
_Avoid_: Polling loop, timer thread

**Login Item Service**:
The system service registering the application for automatic launch upon user login into macOS.
_Avoid_: Auto-start script, crontab, startup item
**Volume Auto-Discovery**:
The dynamic enumeration of non-system mounted external user drives under `/Volumes` available for selection and monitoring.
_Avoid_: Static volume list, hardcoded disk names
