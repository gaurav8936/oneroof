# Security

## Reporting a vulnerability

Please report security problems privately, not in a public issue: use **GitHub › Security › Report a vulnerability**
on this repository (private vulnerability reporting). Include what you found, how to reproduce it, and the One Roof
version (One Roof › About).

You will get a reply within a few days. Fixes ship in a new release, with credit if you want it.

## What One Roof does with your data

- Everything runs on your Mac. One Roof reads your agents' terminals, your git repositories and the folders you choose
  in Settings; it sends nothing to any server of ours (there is none).
- Network use is limited to what you turn on: Linear (if you add a key), and the agent CLIs themselves.
- Keys you enter (for example a Linear API key) are stored in a file only your user can read
  (`~/.config/oneroof/`), never in the app's settings or logs.
