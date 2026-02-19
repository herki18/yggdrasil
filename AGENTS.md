# Yggdrasil (superproject) - Codex instructions

## Purpose
This repo is a superproject that coordinates multiple independent repositories via submodules.

## Core principles
- We have unlimited time: prioritize correctness and quality over speed.
- Clean break: do not preserve backwards compatibility unless explicitly asked.
- Modern, future-proof choices only.
- Always search the web for the latest information before recommending versions, APIs, tooling, or best practices.
- Work in dirty trees without stopping. Never revert or discard existing changes unless the user explicitly asks for that exact revert.

## Working tree policy
- Do not pause work just because `git status` is dirty.
- Treat all pre-existing edits as intentional user work.
- Never run destructive cleanup commands (`git reset --hard`, `git checkout --`, etc.) unless explicitly requested.
- If a conflict with existing edits blocks progress, adjust your change strategy and continue; only ask the user when absolutely necessary.

## Repo structure
- Submodules live in `repos/` (each is its own Git repo).
- Keep root changes minimal (docs, scripts, orchestration).

## Submodule workflow
- Make changes inside the submodule repo and commit/push there first.
- Then update the submodule pointer in this repo and commit/push.

## Current submodules
- `repos/scripting-engine-rust`
- `repos/web-engine-rust`
- `repos/sunderia` (Unity project)
