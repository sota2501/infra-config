#!/bin/bash
# fox上で実行: zpool 配下の全データセット/zvolをスナップショットし、
# zpool_backup へ増分send/receiveでバックアップする。
# 同一ホスト内のプール間転送のため、SSHは不要。
#
# スナップショット名: @daily-YYYYMMDD
# 保持世代数: 30
#
# 未転送のスナップショットが複数ある場合は、zfs send -I で
# 共通スナップショットから最新までの全中間スナップショットを
# まとめて1ストリームで転送する。
#
# cron登録例(毎日04:30):
#   30 4 * * * /usr/local/bin/zfs-pool-backup.sh >> /var/log/zfs-pool-backup.log 2>&1
set -euo pipefail

SRC_POOL="zpool"
DST_POOL="zpool_backup"
SNAP_PREFIX="daily"
KEEP=30
TODAY="$(date +%Y%m%d)"
SNAP_TAG="${SNAP_PREFIX}-${TODAY}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== ZFS pool backup start ==="
log "Source: ${SRC_POOL} -> ${DST_POOL}"

# ソースプール配下の全子データセット/zvolを列挙(プール自身は除外)。
# zfs list -r はツリー順(親→子)で返すため、親データセットの
# send/receiveが先に完了し、子のreceive時に親が確実に存在する。
datasets="$(zfs list -H -o name -r "${SRC_POOL}" | grep -v "^${SRC_POOL}$")"

if [ -z "${datasets}" ]; then
  log "No child datasets found under ${SRC_POOL}. Nothing to backup."
  exit 0
fi

errors=0

for ds in ${datasets}; do
  # zpool/iris-iscsi/pvc-xxx → iris-iscsi/pvc-xxx(プール名を除いた相対パス)
  rel_path="${ds#${SRC_POOL}/}"
  dst_ds="${DST_POOL}/${rel_path}"

  # 本日分のスナップショットを作成(既にあればスキップ)
  snap="${ds}@${SNAP_TAG}"
  if zfs list -H -o name -t snapshot "${snap}" >/dev/null 2>&1; then
    log "Snapshot already exists: ${snap}"
  else
    log "Snapshot: ${snap}"
    zfs snapshot "${snap}"
  fi

  # ソース側の全dailyスナップショットを時系列順に取得
  src_snaps="$(zfs list -H -o name -t snapshot "${ds}" 2>/dev/null \
    | grep "@${SNAP_PREFIX}-" || true)"

  if [ -z "${src_snaps}" ]; then
    log "SKIP: No daily snapshots on ${ds}"
    continue
  fi

  latest_src="$(echo "${src_snaps}" | tail -1)"

  # バックアップ先が存在するか確認
  if zfs list -H -o name "${dst_ds}" >/dev/null 2>&1; then
    # バックアップ先のdailyスナップショットを取得
    dst_snaps="$(zfs list -H -o name -t snapshot "${dst_ds}" 2>/dev/null \
      | grep "@${SNAP_PREFIX}-" || true)"

    # ソースとバックアップ先で共通の最新スナップショットを探す
    common=""
    for src_s in ${src_snaps}; do
      tag="${src_s##*@}"
      for dst_s in ${dst_snaps}; do
        if [ "${dst_s##*@}" = "${tag}" ]; then
          common="${tag}"
        fi
      done
    done

    if [ -n "${common}" ]; then
      if [ "${latest_src##*@}" = "${common}" ]; then
        log "SKIP: ${ds} is up to date (@${common})"
        # 転送不要でもスナップショットの世代管理は行う
      else
        # 共通スナップショットから最新まで、全中間スナップショットをまとめて送信
        log "Incremental (${common} -> ${latest_src##*@}): ${ds}"
        if ! zfs send -I "${ds}@${common}" "${latest_src}" | zfs receive -F "${dst_ds}"; then
          log "ERROR: Incremental send failed for ${ds}, attempting full re-send"
          zfs destroy -r "${dst_ds}" 2>/dev/null || true
          log "Full re-send: ${ds}"
          if ! zfs send -I "${ds}@$(echo "${src_snaps}" | head -1 | sed 's/.*@//')" "${latest_src}" \
               | zfs receive -F "${dst_ds}" 2>/dev/null; then
            # -I は2つ以上のスナップショットが必要。1つしかなければ通常send
            zfs send "${latest_src}" | zfs receive -F "${dst_ds}" || {
              log "ERROR: Full send failed for ${ds}"
              errors=$((errors + 1))
              continue
            }
          fi
        fi
      fi
    else
      # 共通スナップショットが無い: バックアップ先を破棄して全量再送
      log "No common snapshot for ${ds}, full re-send"
      zfs destroy -r "${dst_ds}" 2>/dev/null || true
      first_src="$(echo "${src_snaps}" | head -1)"
      if [ "${first_src}" = "${latest_src}" ]; then
        zfs send "${latest_src}" | zfs receive -F "${dst_ds}" || {
          log "ERROR: Full send failed for ${ds}"
          errors=$((errors + 1))
          continue
        }
      else
        zfs send "${first_src}" | zfs receive -F "${dst_ds}" && \
        zfs send -I "${first_src}" "${latest_src}" | zfs receive -F "${dst_ds}" || {
          log "ERROR: Full send failed for ${ds}"
          errors=$((errors + 1))
          continue
        }
      fi
    fi
  else
    # 新規データセット: 親の存在を確認して全量send
    dst_parent="$(dirname "${dst_ds}")"
    if ! zfs list -H -o name "${dst_parent}" >/dev/null 2>&1; then
      log "Creating parent dataset: ${dst_parent}"
      zfs create -p "${dst_parent}"
    fi

    first_src="$(echo "${src_snaps}" | head -1)"
    log "Full send (new dataset): ${ds}"
    if [ "${first_src}" = "${latest_src}" ]; then
      zfs send "${latest_src}" | zfs receive -F "${dst_ds}" || {
        log "ERROR: Full send failed for ${ds}"
        errors=$((errors + 1))
        continue
      }
    else
      zfs send "${first_src}" | zfs receive -F "${dst_ds}" && \
      zfs send -I "${first_src}" "${latest_src}" | zfs receive -F "${dst_ds}" || {
        log "ERROR: Full send failed for ${ds}"
        errors=$((errors + 1))
        continue
      }
    fi
  fi

  # 古いdailyスナップショットの削除(ソース側: 直近N件を保持)
  old_src="$(zfs list -H -o name -t snapshot "${ds}" 2>/dev/null \
    | grep "@${SNAP_PREFIX}-" \
    | head -n "-${KEEP}" || true)"
  for old in ${old_src}; do
    log "Remove old snapshot (src): ${old}"
    zfs destroy "${old}" || log "WARN: Failed to destroy ${old}"
  done

  # 古いdailyスナップショットの削除(バックアップ先: 直近N件を保持)
  old_dst="$(zfs list -H -o name -t snapshot "${dst_ds}" 2>/dev/null \
    | grep "@${SNAP_PREFIX}-" \
    | head -n "-${KEEP}" || true)"
  for old in ${old_dst}; do
    log "Remove old snapshot (dst): ${old}"
    zfs destroy "${old}" || log "WARN: Failed to destroy ${old}"
  done
done

if [ "${errors}" -gt 0 ]; then
  log "=== Backup completed with ${errors} error(s) ==="
  exit 1
fi

log "=== Backup completed successfully ==="
