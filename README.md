# emcomm-tools-customizer
Customizations for ETC

## Setup

Before running the installation script, you need to configure your WiFi credentials:

### If using VS Code GitHub Repositories extension (recommended):

1. **Create a local secrets file**:
   - In VS Code, right-click on `secrets.env.template` → Copy
   - Right-click in the file area → Paste  
   - Rename the copy to `secrets.env`
   - **Save this file locally** (not in the GitHub repository workspace)

2. **Edit your local `secrets.env`** with actual WiFi credentials:
   - Replace all placeholder values with your real SSIDs and passwords
   - Set `WIFI_COUNT` to match the number of networks you configure

3. **Copy the local secrets file to the target Ubuntu system** when deploying

### If using traditional git clone:

1. Copy the secrets template file:
   ```bash
   cp secrets.env.template secrets.env
   ```

2. Edit `secrets.env` and replace the placeholder values:
   ```bash
   nano secrets.env
   ```

### Auto-connect Configuration:
- All WiFi networks have auto-connect enabled by default (`yes`)
- To disable auto-connect for a specific network, set its `WIFI_X_AUTOCONNECT="no"`
- Example: `WIFI_2_AUTOCONNECT="no"` for mobile hotspots

### Running the script:
```bash
./install-customizations.sh
```

## Security Note

The `secrets.env` file contains sensitive information and is excluded from git via `.gitignore`. Never commit actual WiFi passwords to the repository. The `secrets.env.template` file provides a template showing the required variable names.

## Important Security Notes

- **Never commit `secrets.env` to GitHub** - it contains sensitive WiFi passwords
- The `.gitignore` file prevents accidental commits of `secrets.env`
- Keep your `secrets.env` file **local only** - transfer it directly to target systems

### Using GitHub Repositories Extension

If you're using VS Code's GitHub Repositories extension:

1. **Create `secrets.env` locally** outside the virtual repository workspace
2. **Store it in a secure location** on your local machine
3. **Transfer it directly** to the Ubuntu system when deploying (via SCP, USB, etc.)
4. The virtual workspace prevents accidental commits automatically

### If secrets.env was accidentally committed

For traditional git users, if `secrets.env` was accidentally committed:

1. Remove from git tracking:
   ```bash
   git rm --cached secrets.env
   git commit -m "Remove secrets.env - contains sensitive data"
   git push origin main
   ```

2. Recreate locally:
   ```bash
   cp secrets.env.template secrets.env
   # Edit with your actual credentials
   ```
