# Setup RHEL Image Repository Role

このroleはRHELローカルリポジトリの設定とSubscription Managerの管理を統合して行います。

## 機能
- ISO/CD-ROMのマウント（ループバックまたは物理デバイス）
- BaseOSリポジトリの定義
- AppStreamリポジトリの定義
- マウント内容の検証
- Red Hat Subscription Managerのリポジトリ制御無効化
- DNFメタデータのクリーンアップ

## 動作モード
1. **LOOP_ISO**: ローカルISOファイルをループバックマウント
2. **EXISTING_CDROM**: 物理CD-ROMデバイスを使用

## 変数

### ISO/CD-ROM設定
- `rhel_installer_iso`: ISOファイル名（空の場合はCD-ROM使用）
- `iso_device_path`: CD-ROMデバイスパス（デフォルト: /dev/cdrom）
- `iso_mount_point`: マウントポイント（デフォルト: /mnt/cdrom）

### リポジトリ設定
- `baseos_repo_name`: BaseOSリポジトリ名（デフォルト: BaseOS）
- `baseos_repo_file`: BaseOSリポジトリファイル名
- `baseos_repo_description`: BaseOSリポジトリの説明
- `appstream_repo_name`: AppStreamリポジトリ名（デフォルト: AppStream）
- `appstream_repo_file`: AppStreamリポジトリファイル名
- `appstream_repo_description`: AppStreamリポジトリの説明
- `rhel_gpg_key_path`: GPGキーのパス

### Subscription Manager設定
- `rhsm_manage_repos`: リポジトリ管理の設定（0=無効, 1=有効）

## 使用例
```yaml
# ローカルISOを使用する場合
- hosts: localhost
  roles:
    - setup_rhel_image_repository
  vars:
    rhel_installer_iso: "rhel-8.8-x86_64-dvd.iso"

# CD-ROMを使用する場合（デフォルト）
- hosts: localhost
  roles:
    - setup_rhel_image_repository
```

## 処理フロー
1. ISO設定の判定（ローカルファイル vs CD-ROM）
2. マウントポイントの作成
3. ISO/CD-ROMのマウント
4. マウント内容の検証
5. BaseOSとAppStreamリポジトリの定義
6. Subscription Managerの無効化
7. DNFメタデータのクリーンアップ
