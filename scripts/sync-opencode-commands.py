#!/usr/bin/env python3
import os
import re
import json

def strip_comments(jsonc_str):
    # Remove block comments
    jsonc_str = re.sub(r'/\*.*?\*/', '', jsonc_str, flags=re.DOTALL)
    # Remove line comments
    lines = jsonc_str.split('\n')
    cleaned_lines = []
    for line in lines:
        if '//' in line:
            line = line.split('//')[0]
        cleaned_lines.append(line)
    return '\n'.join(cleaned_lines)

def main():
    repo_dir = "/home/gsinvest000/gs-claude-config"
    commands_dir = os.path.join(repo_dir, "commands")
    opencode_config_path = os.path.expanduser("~/.config/opencode/opencode.jsonc")

    config = {"$schema": "https://opencode.ai/config.json"}
    if os.path.exists(opencode_config_path):
        with open(opencode_config_path, "r", encoding="utf-8") as f:
            content = f.read()
            cleaned = strip_comments(content)
            # Remove trailing commas
            cleaned = re.sub(r',\s*([\]}])', r'\1', cleaned)
            try:
                config = json.loads(cleaned)
            except Exception as e:
                print(f"Error parsing existing opencode.jsonc: {e}. Starting with default schema.")

    if "command" not in config:
        config["command"] = {}

    # Scan commands/
    for filename in sorted(os.listdir(commands_dir)):
        if not filename.endswith(".md"):
            continue
        
        cmd_name = filename[:-3]
        filepath = os.path.join(commands_dir, filename)
        
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()

        # Parse frontmatter
        fm_match = re.match(r'^---\r?\n(.*?)\r?\n---\r?\n(.*)$', content, re.DOTALL)
        if not fm_match:
            print(f"Skipping {filename}: Frontmatter not found.")
            continue
            
        fm_text = fm_match.group(1)
        body = fm_match.group(2).strip()
        
        description = ""
        desc_match = re.search(r'^description:\s*(.*)$', fm_text, re.MULTILINE)
        if desc_match:
            description = desc_match.group(1).strip()
            
        cmd_entry = {
            "template": body
        }
        if description:
            cmd_entry["description"] = description

        # Map known commands to their subagents in opencode
        known_agents = ["quant-researcher", "review-strategy", "daily-summary", "git-tag", "language-tutor"]
        if cmd_name in known_agents:
            cmd_entry["agent"] = cmd_name

        config["command"][cmd_name] = cmd_entry
        print(f"Registered command: /{cmd_name}")

    # Configure external directories in permission settings so opencode can seamlessly
    # work across sibling repositories just like Claude Code.
    if "permission" not in config:
        config["permission"] = {}
        
    config["permission"]["external_directory"] = {
        "/home/gsinvest000/gs-zipline-tej/**": "allow",
        "/home/gsinvest000/gs-strategy/**": "allow",
        "/home/gsinvest000/gs-auto-fix/**": "allow",
        "/home/gsinvest000/quant-research-skill/**": "allow",
        "/home/gsinvest000/tutorial/**": "allow",
        "/home/gsinvest000/gs-claude-config/**": "allow",
        "*": "ask"
    }

    # Write back to ~/.config/opencode/opencode.jsonc
    with open(opencode_config_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")
        
    print(f"Successfully updated opencode.jsonc at {opencode_config_path}")

if __name__ == "__main__":
    main()
