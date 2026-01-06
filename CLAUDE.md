# Yggdrasil (superproject) - Claude instructions

## Overview
Yggdrasil is a superproject that aggregates multiple repos via git submodules under `repos/`.
Keep root-level changes focused on orchestration (docs, scripts, CI), not product code.

## Principles
- Unlimited time: optimize for correctness and quality.
- Clean break: no backwards compatibility unless explicitly requested.
- Modern, future-proof approaches only.
- Always search the web for the latest information before advising on versions, APIs, or tooling.

## Submodule workflow
1. Edit/commit/push inside the submodule repo first.
2. Update the submodule pointer in Yggdrasil and commit/push.

## Current submodules
- `repos/scripting-engine-rust`
- `repos/web-engine-rust`
- `repos/sunderia` (Unity project)
