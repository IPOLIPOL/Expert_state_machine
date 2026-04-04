# Diesel Fuel System State machine 
> (with CLIPS Expert System)

## General architecture of the Expert systems* 
> * with a "static" knowledge base. 
> "dynamic" expert system have additional module for learning new rules/facts.
```
+------------------------+      +----------------------+       +----------------------+ 
|     KNOWLEDGE BASE     |      |   WORKING MEMORY     |       |        USER          |
|                        |      |                      |       |        (REPL)        |
|  +------------------+  |      |   +--------------+   |       |                      |
|  |    FACTS         |  |      |   |   FACTS      |   |       | (start-bunker-pump)  |  
|  | (deffacts,       |  |----->|   | (initial     |   |<------|  (step)              |
|  |  initial facts,  |  |      |   |  facts +     |   |       |  (status)            |
|  |  templates)      |  |      |   |  derived     |   |       |                      | 
|  +------------------+  |      |   |  facts)      |   |       |                      |
|  +------------------+  |      |   +--------------+   |------>|  stdout              |   
|  |    RULES         |  |      |                      |       |                      |
|  | (defrule)        |  |----->|                      |       |                      |
|  |  IF-THEN         |  |      |                      |       |                      |
|  +------------------+  |      |                      |       |                      |
+------------------------+      +----------+-----------+       +----------------------+
                                           |
                                           |  (RETE match)
                                           v
                                +----------------------+
                                |   INFERENCE ENGINE   |
                                |                      |
                                |                      |
                                |   +-------------+    |
                                |   |    RETE     |    |
                                |   |  (rule      |    |
                                |   |   network)  |    |
                                |   +-------------+    |
                                |                      |
                                +----------------------+

```
#### Explanation
1. Knowledge Base contains __static__ facts (initial facts from deffacts) and rules (defrule) that define the system's logic.
2. Working Memory holds __dynamic__ facts – these are initial facts (loaded from the knowledge base) plus derived facts (produced by rules during execution). Facts from the knowledge base are copied to working memory when (reset) is called.
- The user does not directly assert new facts. Instead, the user enters commands (e.g., (start-bunker-pump), (step), (set-volume 5000)).
- These commands trigger control functions that modify existing facts – for example, changing the state slot of a pump fact or the volume slot of the tank fact.
- Rules then react to these modifications and may produce new derived facts (e.g., an alarm fact or a log entry).
- So the facts in working memory evolve from the initial set through rule‑driven updates and user‑command‑driven modifications, not by direct fact entry.
3. Inference Engine (RETE algorithm) matches facts in working memory against the conditions (left‑hand sides) of rules. When a match is found, the rule is placed on the agenda and fired, potentially changing facts and triggering further matches.
4. User enters commands through the REPL (Read‑Eval‑Print Loop) that trigger control functions. These functions modify facts, which initiates a chain of rule executions. The results (status, messages) are returned to the user.

This architecture allows the system to react to changes and automatically derive new facts (e.g., "pump must stop") without imperative step‑by‑step programming.

Diesel Fuel System State Machine
==============================

A simulator of a fuel tank system with two pumps, level setpoints, alarms, and three operating modes: **NORMAL**, **MAINTENANCE**, **FIRE**.

## Features

- Models a tank with a capacity of 20,000 L and initial volume of 9,000 L.
- Two pumps:
  - **Bunker pump** – fills the tank (+600 L/step).
  - **Transfer pump** – empties the tank (–400 L/step).
- Four level setpoints (LSHH, LSH, LSL, LSLL) with corresponding alarms.
- Automatic pump shutdown when critical levels are reached (in NORMAL mode).
- Three user‑selectable operating modes via the `(set-mode ...)` command.
- Full event logging and interactive control through the CLIPS REPL.

## Conceptual Architecture

The program is built as a **production rule expert system** (IF–THEN rules). All data is stored in working memory as facts, and the logic is expressed by independent rules that fire automatically when facts change.

### Main Components

| Component | Purpose |
|-----------|---------|
| **Global constants** | Capacity, setpoints, pump rates, step counter. |
| **Facts (working memory)** | Current volume and level zone, pump states, active alarms, event log, sequence flags, current mode. |
| **Zoning rules** | Classify the level (LSHH/LSH/NORMAL/LSL/LSLL) whenever volume changes. |
| **Setpoint rules** | In NORMAL mode, stop pumps at LSHH/LSLL, raise alarms, set sequence flags. |
| **Mode rules** | In FIRE mode, instantly stop all pumps and block starts; in MAINTENANCE mode, disable auto‑stop and log ignored setpoints. |
| **Sequence rules** | Detect anomalies: rapid fill from LSLL to LSH, or complete drain after LSHH. |
| **Control functions** | Start/stop pumps, simulation steps, forced volume set, mode change, history/status output, full reset. |

### Simple Data Flow

User → command → control function → facts update → automatic rule firing → facts update → status display

## Operating Modes

| Mode | Behaviour |
|------|-----------|
| **NORMAL** | Auto‑stop pumps at LSHH (bunker) and LSLL (transfer), all alarms active, start blocked at critical levels. |
| **MAINTENANCE** | Auto‑stop disabled, pumps can be started at any level (even from STOPPED‑AUTO), warnings are shown but do not block. |
| **FIRE** | All running pumps are stopped immediately, any start attempts are blocked, a special emergency message is displayed. |

## Available Commands 
>(enter in CLIPS REPL)

| Command | Description |
|---------|-------------|
| `(start-bunker-pump)` | Start the filling pump (if not blocked) |
| `(stop-bunker-pump)` | Stop the filling pump (manual) |
| `(start-transfer-pump)` | Start the emptying pump |
| `(stop-transfer-pump)` | Stop the emptying pump |
| `(step)` | Perform one simulation step and show status |
| `(step-n <n>)` | Perform n steps and show status |
| `(set-volume <litres>)` | Force a volume value (for testing) |
| `(set-mode <MODE>)` | Switch mode (NORMAL, MAINTENANCE, FIRE) |
| `(history)` | Show the event log |
| `(status)` | Show full system status |
| `(reset-system)` | Full reset to initial state |

## Example Session

```clips
CLIPS> (reset)
CLIPS> (run)
CLIPS> (start-bunker-pump)
  Bunker pump RUNNING. (+600 L/step)
CLIPS> (step-n 15)           ; volume becomes 18000 → LSHH
CLIPS> (status)              ; pump is STOPPED-AUTO, alarms active
CLIPS> (set-mode MAINTENANCE)
CLIPS> (start-bunker-pump)   ; starts even at LSHH
  Bunker pump RUNNING. (MAINTENANCE mode: override active)
CLIPS> (set-mode FIRE)       ; pump stops immediately
CLIPS> (start-bunker-pump)   ; blocked
  FIRE MODE: Cannot start bunker pump.
```

## How to Run
1. Install CLIPS 6.4 or later.
2. Load the file `diesel_fuel_system.clp`:

```clips
CLIPS> (clear)
CLIPS> (load "diesel_fuel_system.clp")
CLIPS> (reset)
CLIPS> (run)
```
3. Enter commands from the list above.

## Implementation Notes
- All rules use salience (numeric priority) to control firing order: FIRE → zoning → setpoints → sequences → alarm clearing.
- get-* functions read facts from working memory – they ensure reliable access when only one instance of each fact exists.
- Switching to NORMAL mode automatically resets the lshh-occurred and lsll-occurred flags so that sequences can be detected again.
- Pump auto‑stop logic depends only on NORMAL mode and is independent of flag history.

## License
© Ildar Polyakov 2026. All rights reserved.