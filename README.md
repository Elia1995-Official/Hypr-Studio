# Hypr Studio
Visual editor for the Quickshell bar/panels and Hyprland config, plus the HyprGlass settings tool.
Live files live under `~/.local/{bin,lib}` and `~/.config/{quickshell,hypr}`; this repo is a versioned copy.

- `./sync.sh`      copy live files here and commit
- `./sync.sh -b`   same, plus a dated tar.gz in `~/Backups/hypr-studio/`
- `./sync.sh -r`   restore the repo's files over the live ones
- `MANIFEST`       the list of tracked files (edit to add more)
- `DOCUMENTATION.md`  full documentation: architecture, Studio, canvas reference, HyprGlass, troubleshooting
- `DOCUMENTATION.md`  full documentation of the rice, Hypr Studio and HyprGlass

Not included: the HyprGlass plugin itself (third-party, rebuilt from `hyprnux/hyprglass` branch `hyprland-0.56`
into `~/.local/share/hyprglass`; see `.config/hypr/glass.lua` for how it is loaded).
