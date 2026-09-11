# Immich (LXC 106)

Immich is **not** a Docker stack. It is a native install produced by the
[community-scripts ProxmoxVE helper](https://github.com/community-scripts/ProxmoxVE/blob/main/ct/immich.sh)
on its own container, so nothing in `stacks/` applies to it and `make deploy` cannot touch it.
Terraform defines the container in [terraform/lxc.tf](../terraform/lxc.tf); everything inside it
and the host-side mount described below are managed by hand.

| | |
| --- | --- |
| Container | LXC 106, `immich.lan` / `10.66.1.231`, Debian 13, privileged |
| Public URL | `https://photos.zdraganov.work` via the `proxy` stack |
| App | `/opt/immich/app`, source tree in `/opt/immich/source`, env in `/opt/immich/.env` |
| Services | `immich-web`, `immich-ml` (systemd), local PostgreSQL 16 + VectorChord, redis |
| Logs | `/var/log/immich/web.log`, `/var/log/immich/ml.log` |
| Media | `/mnt/Photos` inside the container (see below) |
| Version marker | `/root/.immich` inside the container |

## Media storage

Media lives on the TrueNAS share `//truenas.lan/Photos`, reached through a **dedicated** CIFS mount on
the Proxmox host that is bind-mounted into the container as `mp0`:

```
host:      //truenas.lan/Photos  →  /mnt/immich-photos   (fstab, uid=999,gid=991)
container: /mnt/immich-photos    →  /mnt/Photos          (mp0 in /etc/pve/lxc/106.conf)
```

Do **not** point the container at the Proxmox storage mount `/mnt/pve/Photos`. Proxmox mounts CIFS
storages as root with mode 0755 and offers no uid/gid options, so the `immich` user (uid 999, gid 991)
cannot write there. That is why the original setup silently kept 4.2 GB of photos on the container's
20 GB root disk until September 2026.

Host-side pieces, all on `pve`:

- `/etc/fstab`:

  ```
  //truenas.lan/Photos  /mnt/immich-photos  cifs  guest,vers=3.1.1,uid=999,gid=991,file_mode=0660,dir_mode=0770,iocharset=utf8,_netdev,nofail  0  0
  ```

- `/mnt/immich-photos` is `chattr +i` while unmounted, so if the share is missing at boot Immich fails
  its mount checks instead of writing onto the host disk.
- `/etc/systemd/system/pve-guests.service.d/immich-photos.conf` orders guest startup after the mount:

  ```ini
  [Unit]
  After=mnt-immich\x2dphotos.mount
  Wants=mnt-immich\x2dphotos.mount
  ```

- Container mount: `pct set 106 -mp0 /mnt/immich-photos,mp=/mnt/Photos`. Terraform ignores mount
  changes on existing containers, so `lxc.tf` only documents it.

Verify from the workstation:

```bash
make exec ID=106 CMD="df -h /mnt/Photos"      # must show //truenas.lan/Photos, not the root LV
```

## Updating

Run the helper's updater inside the container. It rebuilds Immich from source, may recompile the
image libraries (2–15 min each) and upgrades VectorChord, so expect 20–60 minutes and run it in tmux:

```bash
ssh -t root@pve.lan tmux new -s immich
pct enter 106
update                       # or: PHS_SILENT=1 update  for a non-interactive run
```

Before a major version:

```bash
# on pve: container backup (snapshots are refused because of the bind mount)
vzdump 106 --mode snapshot --compress zstd --storage local
# inside 106: database dump
sudo -u postgres pg_dump -Fc immich > /root/immich-pre-<ver>.dump
```

Known pitfalls:

- The helper pins the Immich and VectorChord versions it has tested; you cannot pick a version.
- If the Debian `testing` repo is already present the helper skips `apt update` and can 404 on stale
  package versions. Run `apt-get update` inside the container first.
- `make exec`/`make shell` reach the host through the key in `config.mk` (`SSH_KEY`, the public half of
  the agent-held Proxmox key); `ssh root@pve.lan` directly works too.

Rollback: `pct restore 106 local:backup/<vzdump archive> --force`. The media share is not part of the
archive and is unaffected.

## History

- 2026-01-12 — installed via community-scripts (Immich 2.4.1).
- 2026-09-11 — upgraded to 3.2.0 (VectorChord 0.5.3 → 1.1.1). Media moved from the root disk to the
  TrueNAS share as described above; the old copy was left at `/mnt/Photos.local-old-2026-09-11` on the
  container's rootfs (hidden under the mount) and can be deleted via `pct mount 106`.
