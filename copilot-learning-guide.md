# Using AI to Create Your Own Customizations

> **For Absolute Beginners:** This guide teaches you how to use GitHub Copilot
> to write your own bash scripts and customizations. No coding experience
> required—just follow along and learn by doing!

---

## Realistic Expectations: AI Is Powerful, Not Magic

Before diving in, let's set honest expectations about what AI-assisted development looks like in practice.

### This Project's Real Numbers

| Metric | Value |
|--------|-------|
| **Total development time** | ~40-50 hours over 3.5 months |
| **Git commits** | 63 |
| **Lines of bash code** | ~2,100 |
| **Lines of documentation** | ~1,500 |
| **Major rewrites** | 3 (Cubic GUI → xorriso, dry-run removal, template sync) |

### What AI Does Well

- **Generates working code quickly** — First drafts appear in seconds
- **Explains unfamiliar concepts** — Ask "why" and get clear answers
- **Catches errors you'd miss** — ShellCheck + Copilot finds bugs fast
- **Handles boilerplate** — Repetitive patterns are effortless
- **Remembers context** — No need to re-explain your project each session

### What AI Doesn't Do

- **Understand your actual hardware** — It doesn't know your radio setup
- **Test in your environment** — You still run and debug
- **Make architectural decisions** — You choose the approach
- **Know upstream project internals** — ETC's template system required research
- **Guarantee correctness** — AI confidently generates wrong code sometimes

### The Real Workflow

1. **AI generates code** (5 minutes)
2. **You test it** (10 minutes)  
3. **Something fails** (always)
4. **You investigate** (20 minutes)
5. **AI helps fix it** (5 minutes)
6. **Repeat steps 2-5** (hours)
7. **Finally works** (satisfaction!)

**The honest truth:** AI accelerates development 3-5x, but doesn't eliminate the learning curve. This project would have taken 150+ hours without Copilot, but it still took 40-50 hours *with* it.

If someone tells you AI writes perfect code on the first try, they're either lying or building something trivial.

---

## What This Guide Is About

This is NOT documentation for the emcomm-tools-customizer project—see
[README.md](README.md) for that.

This guide teaches you how to use **AI assistance (GitHub Copilot)** to:

- Write bash scripts for any Linux customization
- Create configuration files for ham radio applications
- Manage sensitive data like WiFi passwords securely
- Document your work in Markdown
- Learn programming concepts through conversation with AI

**The Goal:** Empower you to create YOUR OWN customizations, not just use
someone else's scripts.

---

## Why Use AI for Scripting?

### The Old Way

1. Google "how to configure WiFi on Ubuntu"
2. Find 5 different tutorials, all slightly outdated
3. Copy-paste commands you don't understand
4. Something breaks, you have no idea why
5. Start over with a different tutorial

### The Copilot Way

1. Ask: "Write a bash script to configure WiFi on Ubuntu 22.04"
2. Copilot generates a complete script with explanations
3. Ask: "Why does this use nmcli instead of editing files directly?"
4. Copilot explains the reasoning
5. Ask: "Add error handling and logging"
6. Copilot updates the script
7. You understand what you're running AND can modify it

**Key Insight:** Copilot is a teacher, not just a code generator. Ask "why"
questions to learn, not just "how" questions.


---

## Getting Started

### 1. Sign Up for GitHub

- Go to [GitHub](https://github.com/) and create a free account
- Enable GitHub Copilot in your account settings (free tier available)
- Free tier limits: 50 chat requests/month, 2,000 code completions/month

### 2. Install VS Code

Download [VS Code](https://code.visualstudio.com/download) for your OS.

VS Code is a free code editor from Microsoft. Think of it as Notepad with
superpowers—syntax highlighting, error checking, and AI assistance built in.

### 3. Install Essential Extensions

Open VS Code and install these extensions (click the Extensions icon in the
left sidebar):

**Required for Copilot:**

- [GitHub Copilot](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot)
- [GitHub Copilot Chat](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat)

**Recommended for Bash Scripting:**

- [ShellCheck](https://marketplace.visualstudio.com/items?itemName=timonwong.shellcheck) - Catches common bash errors
- [Bash IDE](https://marketplace.visualstudio.com/items?itemName=mads-hartmann.bash-ide-vscode) - Syntax highlighting

**Recommended for Documentation:**


- [Markdown All in One](https://marketplace.visualstudio.com/items?itemName=yzhang.markdown-all-in-one)
- [GitHub Markdown Preview](https://marketplace.visualstudio.com/items?itemName=bierner.github-markdown-preview)

**Optional but Useful:**

- [YAML](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml) - For config files
- [Rainbow CSV](https://marketplace.visualstudio.com/items?itemName=mechatroner.rainbow-csv) - For data files

### 4. Connect to GitHub

- Click the Accounts icon (bottom left of VS Code)
- Sign in with GitHub
- Copilot should activate automatically

---

## Your First Script with Copilot

### Example: Configure Dark Mode on Ubuntu

1. **Create a new file:** `File → New File → Save As → configure-dark-mode.sh`

2. **Open Copilot Chat:** Click the Copilot icon in the sidebar (or `Cmd+Shift+I`)

3. **Ask Copilot:**

   ```text
   Write a bash script that enables dark mode on Ubuntu 22.04 using gsettings.
   Include comments explaining what each command does.
   ```

4. **Review the output:** Copilot will generate something like:

   ```bash
   #!/bin/bash
   # Enable dark mode on Ubuntu 22.04

   # Set the color scheme to prefer dark
   gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

   # Set the GTK theme to Yaru-dark
   gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-dark'

   echo "Dark mode enabled!"
   ```

5. **Ask follow-up questions:**
   - "What does gsettings do?"
   - "Will this persist after reboot?"
   - "How do I make this work for all users, not just the current user?"

6. **Iterate:** Ask Copilot to add error handling, logging, or additional features.

---

## Learning Through Conversation

The real power of Copilot is the conversation. Here are example prompts that
help you LEARN, not just get code:

### Understanding Commands

```text
Explain what this command does: gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
```

### Comparing Approaches

```text
What's the difference between using gsettings and editing dconf directly?
Which is better for a script that runs during ISO customization?
```

### Debugging

```text
This script fails with "GSettings: command not found" - why?
```

### Best Practices

```text
What's the proper way to handle errors in a bash script?
Show me how to add logging that writes to a file.
```

### Security Review

```text
Review this script for security issues. Are there any hardcoded secrets
or unsafe practices?
```

---

## Managing Secrets

**NEVER commit passwords, API keys, or other secrets to Git!**

### The Pattern: Template + Secrets File

1. **Create a template** (`config.template.env`):

   ```bash
   # WiFi Configuration
   WIFI_SSID="YOUR_NETWORK_NAME"
   WIFI_PASSWORD="YOUR_PASSWORD"
   ```

2. **Create your actual secrets file** (`config.env`):

   ```bash
   # WiFi Configuration
   WIFI_SSID="MyHomeNetwork"
   WIFI_PASSWORD="SuperSecretPassword123"
   ```

3. **Add to .gitignore:**

   ```text
   config.env
   secrets.env
   *.env
   !*.template.env
   ```

4. **Use in your script:**

   ```bash
   #!/bin/bash
   source ./config.env

   # Now $WIFI_SSID and $WIFI_PASSWORD are available
   nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD"
   ```

### Ask Copilot to Help

```text
Show me how to write a bash script that reads WiFi credentials from an
environment file and configures NetworkManager. The script should:
1. Check if the env file exists
2. Validate that required variables are set
3. Handle errors gracefully
```

---

## Common Scripting Tasks

Here are prompts for tasks you might want to automate. Copy these into
Copilot Chat and modify for your needs.

### System Configuration

```text
Write a bash script that disables the on-screen keyboard accessibility
feature, disables the screen reader, and sets the hostname to a value
from an environment variable. Include error handling and logging.
```

### Application Configuration

```text
Write a bash script that creates a direwolf.conf file for APRS.
The script should read callsign and SSID from environment variables.
Use a heredoc to create the config file.
```

### Package Installation

```text
Write a bash script that installs a list of packages on Ubuntu.
The script should:
- Check if each package is already installed
- Only install missing packages
- Handle apt errors gracefully
- Log what was installed
```

### File Management

```text
Write a bash script that backs up a directory before making changes.
Create a timestamped backup, then apply modifications.
If anything fails, restore from backup.
```

---

## Documenting Your Work

Good documentation helps you remember what you did and helps others learn.

### Ask Copilot to Document

```text
Generate a README.md for this script. Include:
- What the script does
- Prerequisites
- How to configure it
- Example usage
- Troubleshooting tips
```

### Markdown Basics

```markdown
# Heading 1
## Heading 2

**Bold text** and *italic text*

- Bullet point
- Another point

1. Numbered list
2. Second item

`inline code`

​```bash
code block
​```

[Link text](https://example.com)
```

---

## Tips for Effective Copilot Use

### Be Specific

❌ "Write a WiFi script"

✅ "Write a bash script for Ubuntu 22.04 that configures WiFi using
NetworkManager. Read SSID and password from environment variables.
Include error handling for cases where the network isn't found."

### Iterate in Small Steps

Don't try to build everything at once:

1. Start with the basic functionality
2. Add error handling
3. Add logging
4. Add configuration options
5. Add documentation

### Ask "Why" Questions

- "Why did you use `set -euo pipefail` at the start?"
- "Why use `nmcli` instead of `iwconfig`?"
- "What happens if this command fails?"

### Verify the Output

Copilot is helpful but not infallible:

- Use ShellCheck to catch syntax errors
- Test in a VM or container first
- Read the code before running it
- Ask Copilot to explain anything you don't understand

---

## Choosing the Right AI Model

GitHub Copilot gives you access to multiple AI models, each with different
strengths. Choosing the right model for the task can dramatically improve
your results.

### Available Models (as of late 2025)

| Model | Speed | Best For | Quota Cost |
|-------|-------|----------|------------|
| **GPT-4o** | Fast | Quick code generation, simple edits | Low |
| **GPT-4.1** | Fast | General coding, good balance | Low |
| **Claude 3.5 Haiku** | Very Fast | Simple tasks, high volume | Very Low |
| **Claude 3.5 Sonnet** | Medium | Complex reasoning, longer context | Medium |
| **Claude Sonnet 4** | Medium | Best explanations, nuanced analysis | Medium |
| **Claude Opus 4** | Slow | Most capable, complex projects | High |
| **o1** | Slow | Difficult algorithms, multi-step logic | High |
| **o3-mini** | Medium | Math, logic puzzles, reasoning | Medium |

### The Claude Model Family

Anthropic's Claude models come in three tiers—think of them as
good/better/best:

**Claude Haiku** (3.5 Haiku):

- Fastest and cheapest Claude model
- Great for simple, repetitive tasks
- Use when: You need quick answers and speed matters more than depth
- Example: "What's the syntax for a bash if statement?"

**Claude Sonnet** (3.5 Sonnet, Sonnet 4):

- Best balance of speed, capability, and cost
- Excellent for most coding tasks
- Use when: You need thoughtful, well-explained answers
- Example: "Review this script for security issues and explain each problem"

**Claude Opus** (Opus 4):

- Most capable model in the Claude family
- Best for complex, nuanced tasks requiring deep understanding
- Use when: Sonnet isn't giving good enough answers, or for critical code
- Example: "Architect a complete solution for managing radio CAT control
  across multiple applications with proper error handling and logging"

### Model Selection Guide

**For Simple Tasks (use GPT-4o, GPT-4.1, or Claude Haiku):**

- Writing basic bash scripts
- Simple code completions
- Quick syntax fixes
- Straightforward "how do I..." questions

**For Complex Tasks (use Claude Sonnet 4):**

- Understanding large codebases
- Explaining complex concepts
- Writing documentation
- Code review and security analysis
- Multi-file refactoring
- When you need nuanced, thoughtful responses

**For the Most Demanding Tasks (use Claude Opus 4):**

- Architecting complete solutions from scratch
- Critical code that must be correct (safety, security)
- Complex multi-component system design
- When Sonnet's answers aren't quite right
- Tasks requiring deep domain expertise

**For Reasoning-Heavy Tasks (use o1 or o3-mini):**

- Complex algorithms
- Debugging subtle logic errors
- Multi-step problem solving
- When simpler models give wrong answers
- Mathematical or logical puzzles

### How to Switch Models

In VS Code with Copilot Chat:

1. Click the model name in the chat input area
2. Select from the available models
3. Your next message will use that model

**Tip:** Start with a fast model (GPT-4o), and if the answer isn't good
enough, retry with Claude or o1.

### Practical Examples

**Simple script generation → GPT-4o:**

```text
Write a bash function that checks if a file exists
```

**Understanding unfamiliar code → Claude Sonnet 4:**

```text
Explain what this direwolf.conf file does and what each section means.
I'm new to packet radio and need to understand how to configure it.
```

**Debugging complex logic → o1:**

```text
This script should detect all USB serial devices and match them to
known radio models, but it's failing for devices with multiple interfaces.
Help me fix the device enumeration logic.
```

### Cost Awareness

The "reasoning" models (o1, o3-mini) and Opus use significantly more of your quota:

- A single o1 query might use 5-10x the tokens of a GPT-4o query
- Claude Opus uses roughly 3-5x more than Sonnet
- Claude Haiku is the most economical choice for simple tasks
- On the free tier, this matters—use premium models sparingly
- For most bash scripting tasks, GPT-4o or Claude Sonnet is sufficient

### My Recommendations

For ham radio/EmComm scripting:

1. **Default to Claude Sonnet 4** for most questions—it gives better
   explanations and catches edge cases
2. **Use GPT-4o or Claude Haiku** for quick code completions while typing
3. **Escalate to Claude Opus** for complex architecture or critical code
4. **Save o1** for when you're truly stuck on a logic problem
5. **Try multiple models** if the first answer doesn't work

---

## Free Tier Limits

GitHub Copilot Free includes:

- 50 chat messages per month
- 2,000 code completions per month

**Tips to stay within limits:**

- Ask comprehensive questions (get more in fewer messages)
- Use code completions (typing and accepting suggestions) more than chat
- Consider upgrading to Pro ($10/month) if you use it regularly

---

## Final Advice

1. **Use Copilot as a teacher**, not just a code generator
2. **Ask "why" questions** to understand, not just "how" questions
3. **Start small** and iterate
4. **Test everything** before deploying
5. **Never commit secrets** to public repositories
6. **Document your work** so you remember why you made each choice
7. **Share your knowledge** to help the ham radio community

---

## Credits

- **EmComm Tools Community**: [TheTechPrepper](https://github.com/thetechprepper/emcomm-tools-os-community)
- **GitHub Copilot**: [GitHub](https://github.com/features/copilot)
- **This Guide**: KD7DGF

**73 de KD7DGF** 📻
