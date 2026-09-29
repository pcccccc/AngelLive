---
name: jev-ios
description: Give a coding agent fast semantic mobile verification. Inspect or learn an authorized app, map product intent into bounded scenarios, select affected tests, and run them across native or MobAI device fleets without spawning additional coding agents.
---

# Jev iOS

Use Jev as the small decision worker underneath the coding agent.

**You own:** product intent, code changes, fixture authority, acceptance criteria, and interpretation.

**Jev owns:** choosing among explicitly observed controls for a bounded goal.

**The device transport owns:** observation, target resolution, freshness checks, input, and fresh evidence.

**The scheduler owns:** device lanes, claims/leases, fixture locks, API limits, pricing admission, and artifacts.

Do not create another coding-agent session for each device. Do not ask Jev to decide what success means.

## First contact with a repo

When a user points you at Jev and asks you to use it on an app:

1. Read this skill.
2. Read the app repo's own `AGENTS.md`, `CLAUDE.md`, tests, and product requirements.
3. Determine the app bundle ID and existing build/install workflow. Do not invent build commands.
4. Run `jev-ios doctor`.
5. Detect the available device path:
   - If MobAI is configured or the task needs physical, remote, cloud, Android-adjacent, or broad fleet coverage, use MobAI for execution. For first-time scenario authoring on a MobAI-only device, use the coding agent's interactive MobAI tooling/MCP to inspect the semantic UI before writing labels; `jev-ios inspect` and `jev-ios learn` currently target the native Simulator path.
   - Otherwise use native iOS Simulator through AXe + simctl.
6. Run `jev-ios init --bundle-id <bundle>` if the app has no `.jev-ios/` scaffold.
7. Inspect before authoring scenarios. Never guess accessibility labels.
8. Run the smallest useful verification after the change. Scale only when the task warrants it.

If a prerequisite is missing, report the exact missing prerequisite and continue with everything that can be prepared safely. Do not replace the app's build system, credentials, or fixture strategy merely to make Jev run.

## Device-path decision

### Prefer MobAI when available

Use:

```sh
jev-ios mobai-devices
```

MobAI is the recommended substrate for multi-device, physical-device, remote, distributed, or cloud execution. Jev speaks MobAI HTTP/DSL directly at runtime.

Use MobAI for:

- device discovery and routing;
- exclusive device claims;
- compact semantic UI trees;
- predicate-based execution;
- local, physical, remote and cloud devices;
- bridge lifecycle;
- deterministic `.mob` flows;
- CI/device-farm infrastructure.

Keep Jev responsible for dynamic semantic decisions, bounded learning, scenario intent, impact selection, and aggregation.

MobAI MCP is optional for the Jev runtime but recommended when **you**, the coding agent, need to inspect or explore a MobAI-only physical/cloud device before a Jev scenario exists. Do not insert MCP between the Jev scheduler and MobAI during scenario execution.

When a Jev-discovered path becomes stable and deterministic, prefer promoting it to a MobAI `.mob` flow rather than continuing to spend inference on every known step.

### Native local path

Use native AXe + `xcrun simctl` when the job is local iOS Simulator verification and the smaller dependency surface is preferable.

XcodeBuildMCP is not required.

## Learn before guessing

Start with an exact observation:

```sh
jev-ios inspect --udid "$SIMULATOR_UDID" --bundle-id <bundle-id> --launch
```

For an unfamiliar area, use Jev as a bounded semantic scout. First inspect the current screen and identify navigation controls that the caller's task authorizes. Then allow only those labels:

```sh
jev-ios learn \
  --udid "$SIMULATOR_UDID" --bundle-id <bundle-id> \
  --allow-label Settings --allow-label Notifications --allow-label Back \
  --max-steps 8 --budget-usd 0.10 \
  --output .jev-ios/app-map-settings.json
```

Replace the example labels with labels actually observed in the authorized app.

Without an allow-list, learning is observe-only. Learning does not grant itself new authority. A control name is not evidence that activating it is safe.

Treat the resulting app map as orientation, not truth. It is a bounded sample. Runtime target IDs and screen fingerprints are observation-specific and must never become durable selectors.

## Translate intent into a scenario

Start from the user-observable contract, not an implementation plan and not a tap script.

For every scenario determine:

1. **Goal:** what should a user be able to accomplish?
2. **Start evidence:** what exact labels establish the prepared starting state?
3. **Success evidence:** what exact labels distinguish success from the starting/global UI?
4. **Allowed actions:** which observed controls are appropriate for this test?
5. **Fixture text:** what explicit non-sensitive values may be typed?
6. **Scroll authority:** is semantic scrolling actually needed?
7. **Bound:** what is the smallest reasonable step limit?

Example:

```json
{
  "schema": "jev-ios/scenario/v1",
  "name": "Notification settings",
  "goal": "Open notification settings and reach the push-notification controls.",
  "expect_labels": ["Notifications", "Push notifications"],
  "allow_labels": ["Settings", "Notifications"],
  "allow_scroll": false,
  "text_values": {},
  "max_steps": 6,
  "min_probability": 0.55
}
```

Expected labels are assertions. Never weaken them merely because a run failed.

Scenario JSON belongs in the app repository. Do not modify Jev's Python scenario validator to add an app test.

## Decide whether Jev is the right test

Use Jev for semantic mobile flows where navigation is dynamic or expensive for the coding agent to perform itself.

Keep these elsewhere:

| Need | Better owner |
| --- | --- |
| Pure business logic | unit tests |
| API/database effects | integration/API tests |
| Exact pixels/layout | visual testing |
| Accessibility compliance | dedicated accessibility checks |
| Stable known mobile sequence | MobAI `.mob` / deterministic automation |
| Dynamic semantic navigation | Jev |
| Product/release acceptance | human/product-defined acceptance system |

A verified Jev scenario proves its required observed labels for that run. Nothing more.

## Build the suite

A suite adds scheduling metadata without changing scenario semantics.

Map cases to source paths using actual ownership knowledge. Mark critical flows explicitly. Unknown changed paths conservatively select the full suite.

Keep `fixture_isolation: shared` until accounts and backend data are truly independent across devices. Relaunching an app is not a fixture reset.

For device pools, prefer MobAI workers when the fleet is available:

```json
{
  "schema": "jev-ios/pool/v1",
  "devices": [
    {"name": "native-sim", "udid": "<simulator-uuid>"},
    {"name": "mobai-device", "transport": "mobai", "udid": "<mobai-device-id>"},
    {
      "name": "cloud-device",
      "transport": "mobai",
      "udid": "<cloud-device-id>",
      "mobai_url": "https://host.example/api/v1",
      "mobai_app": "<provider-app-ref>"
    }
  ]
}
```

Never put API tokens in pool files. `MOBAI_TOKEN`, gateway credentials, SSH keys, and provider credentials stay in the execution environment.

## Plan before expensive execution

For a change:

```sh
jev-ios plan \
  --suite .jev-ios/suite.json --pool .jev-ios/pool.json \
  --changed-since main --mode shard
```

Read the plan. Check selected cases, omitted cases, devices, fixture isolation, and whether an unmapped source change forced full-suite coverage.

Then execute:

```sh
jev-ios matrix \
  --suite .jev-ios/suite.json --pool .jev-ios/pool.json \
  --changed-since main --mode shard --parallel 4 \
  --api-concurrency 2 --requests-per-second 4 --budget-usd 1
```

Use `shard` for fast affected-flow verification. Use `matrix` only when the scenario × device product is intentional coverage.

More device lanes do not reduce inference count. A matrix multiplies executions by device count.

## Consume results efficiently

Read, in order:

1. final CLI `matrix_result`;
2. `summary.json`;
3. `matrix.json` if machine-readable detail is needed;
4. only the relevant failed cell's `result.json` and `trace.jsonl`;
5. HTML reports when human replay helps.

Do not load every trace into context by default.

Report:

- selection scope;
- app/build provenance when known;
- device/pool scope;
- verified count;
- blocked, uncertain, skipped, or failed outcomes;
- whether the result is semantic UI evidence only.

Similar failure groups are shared symptoms, not proven root causes.

## Diagnose without gaming the test

Classify a non-verified result before editing:

- product behavior;
- incorrect scenario intent;
- missing/weak accessibility semantics;
- fixture or starting state;
- device transport;
- provider/model;
- unsupported verification type.

Do not immediately rewrite the scenario and do not immediately rewrite product code.

Use:

```sh
jev-ios verify --manifest runs/<run>/matrix.json
jev-ios reproduce --manifest runs/<run>/matrix.json --cell <cell-id>
```

Reproduction is dry by default. Inspect the frozen scenario, repair the responsible layer, restore the fixture, then add `--execute` for a fresh run. An uncertain action is never blindly replayed.

## MobAI-specific operating rules

When using MobAI:

- Prefer compact semantic UI state over screenshots.
- Prefer semantic predicates over coordinates.
- Let MobAI claims provide exclusive device ownership.
- Let Jev re-observe before dispatch so stale decisions are rejected.
- Treat a transport failure after input as uncertain.
- Never expose MobAI lease tokens, provider tokens, secure-field labels, or secure-field values to Jev.
- Use `mobai_app` for provider-backed cloud sessions when the MobAI host requires an app ref.
- Use MobAI OCR/screenshots only as targeted fallback/evidence. Do not silently convert them into Jev execution authority.
- Consider `simslim` only as opt-in local-host tuning after qualifying the app.

## Extend the narrowest layer

| Need | Surface |
| --- | --- |
| Add an app flow | scenario JSON in the app repo |
| Source/fixture/device mapping | suite/pool JSON |
| Native Simulator execution | `jev_ios/device.py`, `jev_ios/fleet.py` |
| MobAI transport | `jev_ios/mobai.py` |
| SSH transport | `jev_ios/remote.py` |
| Parallel scheduling | `jev_ios/matrix.py` |
| Learning/onboarding | `jev_ios/learning.py`, `jev_ios/onboarding.py` |
| Jev decisions | `jev_ios/model.py` |
| Verification loop | `jev_ios/runner.py` |
| Reports | `jev_ios/matrix_report.py`, `jev_ios/report.py` |

Before changing runtime code, read `AGENTS.md` and `docs/architecture.md`.

Preserve these invariants:

- the model chooses only offered observed targets;
- target identity survives transport translation;
- secure fields are redacted at the device boundary;
- state is refreshed before input;
- uncertain input is not replayed;
- model calls and steps are bounded;
- success comes from fresh evidence, not a model declaration;
- credentials and host configuration never enter scenarios;
- no model output becomes a shell command, arbitrary coordinate, credential, or authorization.

## Before declaring work complete

For an app change, run the relevant Jev verification when prerequisites are available and report the exact scope.

For Jev runtime changes, run:

```sh
python3 -m unittest discover -s tests -v
node --check examples/brigade-call.mjs
node --test tests/test_brigade.mjs
```

Keep offline contract tests distinct from live device qualification and performance measurements.
