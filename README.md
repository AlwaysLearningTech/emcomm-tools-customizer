# emcomm-tools-customizer
Customizations for ETC

## Setup

Before running the installation script, you need to configure your WiFi credentials:

1. Copy the secrets template file:
   ```bash
   cp secrets.env.template secrets.env
   ```

2. Edit `secrets.env` and replace the placeholder values with your actual WiFi SSIDs and passwords:
   ```bash
   nano secrets.env
   ```

   **Auto-connect Configuration:**
   - All WiFi networks have auto-connect enabled by default (`yes`)
   - To disable auto-connect for a specific network, set its `*_AUTOCONNECT` variable to `no`
   - Example: `IPHONE_WIFI_AUTOCONNECT="no"` to prevent automatic connection to iPhone hotspot

3. Run the installation script:
   ```bash
   ./install-customizations.sh
   ```

## Security Note

The `secrets.env` file contains sensitive information and is excluded from git via `.gitignore`. Never commit actual WiFi passwords to the repository. The `secrets.env.template` file provides a template showing the required variable names.
