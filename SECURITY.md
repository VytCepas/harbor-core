# Security policy

## Reporting a vulnerability

Use GitHub private vulnerability reporting: open this repository's **Security**
tab and choose **Report a vulnerability**. Please do not open a public issue or
pull request for a security finding. No email address is monitored for reports.

## Scope

In scope: the floor guards (`bin/admission-*.sh` and `bin/library-admission.sh`; `bin/guard-*.sh` until 2026-11-15 are links to them) and the installers, meaning any way
to make a guard allow what it should refuse, to disable or bypass one silently,
or to make an installer write outside its stated targets.

Bypass findings of the kind `docs/explanation/admission-baseline.md` already records are wanted: a measured
bypass with a reproducing command is the most useful report. A bypass that
`docs/explanation/admission-baseline.md` lists as an accepted residual is still worth reporting if you can
widen it.

Out of scope: findings that need an attacker who already controls the operator's
account or machine, and third-party code under `vendor/` (report it upstream;
see `NOTICE` for where each tree comes from).
