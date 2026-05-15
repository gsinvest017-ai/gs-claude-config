# Windows Terminal — manual font setup

`chezmoi apply` does NOT touch `~/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` because that file mixes per-user content (font, theme) with per-machine content (WSL distro GUIDs, default profile choice). Risk of wiping a colleague's WT config outweighs the convenience.

After `chezmoi apply` finishes and the font is installed (handled by the bootstrap script), set the font yourself once:

1. Open Windows Terminal → `Ctrl + ,`
2. Profiles → **Defaults** → Appearance → **Font face** → pick `CaskaydiaCove NFM`
3. Save (Ctrl + S)

That's it. New tabs use the Nerd Font; existing tabs need a reopen.

## Why "CaskaydiaCove NFM" and not "CaskaydiaCove Nerd Font Mono"?

The Nerd Font installer registers the family name as `CaskaydiaCove NFM` (NF Mono variant). The longer form is the file name. Use the registered family name in WT settings, otherwise WT silently falls back to its default font and you'll still see `?` glyphs in oh-my-posh prompts.

## (Advanced) Automating it with a modify_ script

chezmoi supports `modify_<path>.ps1.tmpl` scripts that read existing content on stdin and write modified content to stdout. This is the right way to merge font into existing settings.json without overwriting other keys.

A future PR can add `chezmoi-source/AppData/.../modify_settings.json.ps1.tmpl` that:
1. Reads stdin, parses as JSON (PowerShell `ConvertFrom-Json`)
2. Sets `.profiles.defaults.font.face` to `{{ .terminal.nerdFont }}`
3. Writes back via `ConvertTo-Json -Depth 32`

Deferred for now — manual setup is one click and rare.
