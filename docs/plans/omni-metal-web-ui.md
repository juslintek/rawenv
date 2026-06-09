# Omni Metal Web UI — Bare-Metal Hosting Platform

> **Status: PLANNED** — Not yet implemented. Pick up after native GUIs are complete.

---

## Overview

A web-based management UI for bare-metal server provisioning, deployment, and lifecycle management. Combines a Go backend orchestrator with a SolidJS frontend for real-time hardware management at scale.

---

## Go Backend Orchestrator

### Core Components

| Component | Purpose |
|-----------|---------|
| **Matchbox** | PXE/iPXE boot server — serves ignition/cloud-config based on hardware attributes |
| **Tinkerbell Actions** | Workflow execution engine for provisioning steps |
| **Redfish/IPMI Driver** | Hardware power-cycling, BMC interaction, sensor data |
| **iPXE Dynamic Boot Router** | Serve custom iPXE scripts via HTTP based on MAC address |

### Multi-OS Provisioning

| OS | Method |
|----|--------|
| Linux | cloud-init (Ubuntu, Fedora, Debian, Arch) |
| Windows | WIM via wimlib-imagex, unattend.xml |
| macOS | MicroMDM / NanoMDM with EACS (Enrollment Authentication Certificate Service) |

### Machine Lifecycle State Machine

```
discovery → commissioning → deploying → active → deprovisioning
    ↑                                                    │
    └────────────────────────────────────────────────────┘
```

| State | Description |
|-------|-------------|
| `discovery` | Machine PXE boots, registers MAC/serial/hardware profile |
| `commissioning` | Hardware tests, firmware updates, BIOS configuration |
| `deploying` | OS installation in progress |
| `active` | Machine serving workloads |
| `deprovisioning` | Secure wipe, return to pool |

### Hardware Deployment Automation

```yaml
# workflow.yaml
workflows:
  - match:
      hardware: "Mac Mini"
    flow: mdm
    steps:
      - enroll_mdm
      - push_profile
      - install_os
      - verify_boot

  - match:
      hardware: "Generic x86"
    flow: ipxe
    steps:
      - pxe_boot
      - partition_disk
      - install_os
      - configure_network
      - verify_boot
```

---

## SolidJS Frontend

### Design Decisions

| Decision | Rationale |
|----------|-----------|
| **SolidJS** | Fine-grained reactivity (Signals), no Virtual DOM overhead |
| **Vite** | Near-instant HMR during development |
| **Shoelace** | Lightweight, standards-compliant web components |
| **WebSocket** | Real-time streaming for installation logs |

### Performance Target

- Handle **1000+ concurrent server status pings** without frame drops
- Fine-grained Signals update only affected DOM nodes
- No Virtual DOM diffing overhead

### Key Views

- **Fleet Dashboard** — grid of all machines with live status indicators
- **Machine Detail** — hardware info, lifecycle state, logs, actions
- **Workflow Editor** — visual workflow builder for provisioning steps
- **Tenant Management** — resource quotas, allocation, billing
- **Live Logs** — WebSocket-streamed installation/provisioning output

---

## Multi-Tenant Resource Management

| Feature | Description |
|---------|-------------|
| Per-tenant service isolation | Without virtualization or containerization — OS-level isolation |
| Resource quotas | CPU, memory, disk, network per tenant and per service |
| Hardware allocation | Assign physical machines to tenants |
| Scheduling | Fair-share scheduling across tenant workloads |

---

## Development Stack

```yaml
# docker-compose.yaml (development)
services:
  orchestrator:
    build: ./backend
    ports: ["8080:8080"]
    environment:
      - DATABASE_URL=postgres://...

  frontend:
    build: ./frontend
    ports: ["3000:3000"]
    command: npm run dev

  postgres:
    image: postgres:16

  matchbox:
    image: quay.io/poseidon/matchbox
    volumes:
      - ./matchbox/assets:/var/lib/matchbox/assets

  tinkerbell:
    image: quay.io/tinkerbell/tink-server
```

---

## Architecture Principles

Same SOLID / YAGNI / KISS / DRY principles from [AGENTS.md](../../AGENTS.md) apply to this subsystem.

- Backend: Clean Architecture (handlers → services → repositories)
- Frontend: Component-based with Signals for state, no global store unless necessary
- Testing: Go table-driven tests, Playwright for frontend e2e
- API: REST + WebSocket, OpenAPI spec generated from Go types

---

## Dependencies

| Backend | Frontend |
|---------|----------|
| Go 1.22+ | SolidJS 1.8+ |
| Matchbox | Vite 5+ |
| Tinkerbell | Shoelace 2.x |
| gofish (Redfish client) | WebSocket (native) |
| wimlib-imagex | Playwright (testing) |
| MicroMDM/NanoMDM | |

---

## Status

**PLANNED** — This document captures the design intent. Implementation begins after native GUI platforms (macOS, Linux, Windows) are complete and stable.
