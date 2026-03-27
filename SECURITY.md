# Security Policy

## Supported Scope

This repo is a shell-based server management toolkit. Security-sensitive areas include:

- command execution and shell escaping
- file copy/move/delete behavior
- config parsing and path handling
- secrets handling in local environment files

## Reporting

Please do not open public issues for suspected security problems.

Report security concerns privately through GitHub security advisories or direct maintainer contact if that is configured for the repository.

When reporting, include:

- what script or command path is affected
- the risky behavior
- how it can be reproduced
- impact and any suggested mitigation

## Handling Secrets

- Do not commit `Scripts/env.sh`
- Do not commit real tokens, webhook URLs, or account credentials
- Treat `Configs/serverconfig.txt` as local machine-specific config unless explicitly sanitized
