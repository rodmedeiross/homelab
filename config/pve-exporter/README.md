# PVE Exporter Configuration

## Setup Instructions

1. **Copy the template and configure:**
   ```bash
   # On the target host, edit the configuration file
   nano config/pve-exporter/pve.yml
   ```

2. **Update the following values:**
   - `password: CHANGE_ME_TO_YOUR_ACTUAL_PASSWORD` → Your monitoring user password
   - `target: CHANGE_ME_TO_YOUR_PROXMOX_HOST` → Your Proxmox hostname/IP

3. **Create the monitoring user in Proxmox:**
   ```bash
   # SSH to your Proxmox host and run:
   pveum user add monitoring@pve --password 'YourSecurePassword123!'
   pveum aclmod / --user monitoring@pve --role PVEAuditor
   ```

4. **Exclude from Git tracking (on target host):**
   ```bash
   git update-index --skip-worktree config/pve-exporter/pve.yml
   ```

## Security Notes

- **Never commit real credentials** to version control
- The `pve.yml` file should be excluded from Git tracking on production hosts
- Use strong passwords for the monitoring user
- Consider using `verify_ssl: true` with proper certificates in production

## Example Configuration

```yaml
default:
  user: monitoring@pve
  password: YourSecurePassword123!
  verify_ssl: false
  target: proxmox.yourdomain.com
  port: 8006
```
