SHELL := /bin/bash -o pipefail
.DEFAULT_GOAL := help

BUNDLE := offline-resources
IMG_DIR := /var/lib/libvirt/images
INVENTORY := /tmp/airgap-test-inventory.yml
SSH_EXTRA := -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

# VM settings
REPO_MAC := 52:54:00:AA:BB:05
RHEL_MAC := 52:54:00:AA:BB:10
WIN_MAC  := 52:54:00:AA:BB:20

.PHONY: help setup-network setup-vms setup-rhel-vms setup-win-vm \
        destroy-vms destroy-rhel-vms destroy-win-vm \
        transfer-rhel transfer-win \
        deploy-repo deploy-rhel deploy-win deploy-all \
        verify-airgap verify-rhel verify-win \
        test clean full-test

help: ## ヘルプを表示
	@echo "=== Airgap 研修環境管理 ==="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

# --- ネットワーク ---

setup-network: ## 隔離ネットワークを作成
	@if sudo virsh net-info airgap-training >/dev/null 2>&1; then \
		echo "airgap-training: already exists"; \
	else \
		sudo virsh net-define kvm/create-airgap-network.xml; \
		sudo virsh net-start airgap-training; \
		sudo virsh net-autostart airgap-training; \
		echo "airgap-training: created"; \
	fi

# --- VM 作成 ---

setup-rhel-vms: setup-network ## RHEL VM (repo-server + rhel-target) を作成・起動
	@echo "=== RHEL VM 作成 ==="
	@for vm in repo-server rhel-target; do \
		if sudo virsh dominfo $$vm >/dev/null 2>&1; then \
			echo "$$vm: already exists"; \
			continue; \
		fi; \
		cp $(BUNDLE)/vm-images/rhel-10.2-x86_64-kvm.qcow2 /tmp/$$vm.qcow2; \
		if [ "$$vm" = "rhel-target" ]; then \
			EXTRA="--run-command 'dnf remove -y podman 2>/dev/null; true'"; \
		else \
			EXTRA=""; \
		fi; \
		sudo virt-customize -a /tmp/$$vm.qcow2 \
			--root-password password:password --hostname $$vm \
			--run-command 'sed -i "s/#PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config' \
			--run-command 'systemctl enable sshd' \
			$$EXTRA --selinux-relabel 2>&1 | grep Finishing || { echo "ERROR: virt-customize failed for $$vm"; exit 1; }; \
		sudo qemu-img resize /tmp/$$vm.qcow2 20G 2>&1; \
		sudo mv /tmp/$$vm.qcow2 $(IMG_DIR)/$$vm.qcow2; \
	done
	@echo "=== VM 起動 ==="
	@sudo virsh dominfo repo-server >/dev/null 2>&1 && sudo virsh start repo-server 2>/dev/null || \
		sudo virt-install --name repo-server --import \
			--disk path=$(IMG_DIR)/repo-server.qcow2,format=qcow2 \
			--memory 2048 --vcpus 2 --os-variant rhel10.0 \
			--network network=airgap-training,mac=$(REPO_MAC) \
			--graphics vnc --noautoconsole 2>&1 | tail -1
	@sudo virsh dominfo rhel-target >/dev/null 2>&1 && sudo virsh start rhel-target 2>/dev/null || \
		sudo virt-install --name rhel-target --import \
			--disk path=$(IMG_DIR)/rhel-target.qcow2,format=qcow2 \
			--memory 4096 --vcpus 2 --os-variant rhel10.0 \
			--network network=airgap-training,mac=$(RHEL_MAC) \
			--graphics vnc --noautoconsole 2>&1 | tail -1
	@echo "Waiting for VMs..."; sleep 15
	@sudo virsh domifaddr repo-server | grep ipv4
	@sudo virsh domifaddr rhel-target | grep ipv4

setup-win-vm: setup-network ## Windows VM を作成・起動
	@echo "=== Windows VM 作成 ==="
	@if sudo virsh dominfo win11-airgap >/dev/null 2>&1; then \
		echo "win11-airgap: already exists"; \
		sudo virsh start win11-airgap 2>/dev/null || true; \
	else \
		sudo cp $(BUNDLE)/vm-images/windows-11-25h2.qcow2 $(IMG_DIR)/win11-airgap.qcow2; \
		sudo virt-install --name win11-airgap --import \
			--disk path=$(IMG_DIR)/win11-airgap.qcow2,format=qcow2 \
			--memory 8192 --vcpus 4 --os-variant win11 \
			--network network=airgap-training,mac=$(WIN_MAC) \
			--features hyperv.relaxed.state=on,hyperv.vapic.state=on,hyperv.spinlocks.state=on,hyperv.spinlocks.retries=8191 \
			--cpu host-passthrough \
			--boot uefi --graphics vnc --noautoconsole 2>&1 | tail -1; \
	fi
	@echo "Waiting for Windows VM..."; sleep 30
	@sudo virsh domifaddr win11-airgap | grep ipv4 || echo "(IP not yet available)"

setup-vms: setup-rhel-vms setup-win-vm ## 全 VM を作成・起動

# --- VM 削除 ---

destroy-rhel-vms: ## RHEL VM を削除
	@for vm in repo-server rhel-target; do \
		sudo virsh destroy $$vm 2>/dev/null || true; \
		sudo virsh undefine $$vm 2>/dev/null || true; \
		sudo rm -f $(IMG_DIR)/$$vm.qcow2; \
		echo "$$vm: destroyed"; \
	done

destroy-win-vm: ## Windows VM を削除
	@sudo virsh destroy win11-airgap 2>/dev/null || true
	@sudo virsh undefine win11-airgap --nvram 2>/dev/null || true
	@sudo rm -f $(IMG_DIR)/win11-airgap.qcow2
	@echo "win11-airgap: destroyed"

destroy-vms: destroy-rhel-vms destroy-win-vm ## 全 VM を削除

# --- リソース転送 ---

transfer-rhel: ## RHEL VM にリソースを転送
	@echo "=== ディスク拡張 ==="
	@for host in repo-server rhel-target; do \
		echo "  $$host:"; \
		ansible -i $(INVENTORY) $$host -m shell \
			-a 'TMPDIR=/dev/shm growpart /dev/vda 3 2>/dev/null || true; xfs_growfs / 2>/dev/null || true; avail=$$(df --output=avail / | tail -1); echo "AVAIL_KB:$$avail"; [ "$$avail" -gt 10000000 ] && echo "DISK_OK" || echo "DISK_LOW"' \
			-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | grep -E 'AVAIL_KB|DISK_OK|DISK_LOW'; \
	done
	@echo "=== DVD ISO → repo-server ==="
	@ansible -i $(INVENTORY) repo-server -m copy \
		-a "src=$(BUNDLE)/iso/rhel-10.2-x86_64-dvd.iso dest=/opt/rhel10.iso" \
		-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | grep -E 'changed|ok'
	@echo "=== Packages → repo-server ==="
	@ansible -i $(INVENTORY) repo-server -m file \
		-a "path=/opt/airgap-bundle/packages state=directory" \
		-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | tail -1
	@if [ -d "$(BUNDLE)/packages" ] && [ -n "$$(ls -A $(BUNDLE)/packages/ 2>/dev/null)" ]; then \
		ansible -i $(INVENTORY) repo-server -m copy \
			-a "src=$(BUNDLE)/packages/ dest=/opt/airgap-bundle/packages/" \
			-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | grep -E 'changed|ok'; \
	else echo "  packages/ is empty, skipping"; fi
	@echo "=== Bundle → rhel-target ==="
	@ansible -i $(INVENTORY) rhel-target -m file \
		-a 'path=/opt/airgap-bundle state=directory' -e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | tail -1
	@for d in container-images binaries training-materials; do \
		ansible -i $(INVENTORY) rhel-target -m file \
			-a "path=/opt/airgap-bundle/$$d state=directory" \
			-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | tail -1; \
	done
	@ansible -i $(INVENTORY) rhel-target -m copy \
		-a "src=$(BUNDLE)/container-images/training-controller.tar dest=/opt/airgap-bundle/container-images/" \
		-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | grep -E 'changed|ok'
	@ansible -i $(INVENTORY) rhel-target -m copy \
		-a "src=$(BUNDLE)/container-images/training-linux-node.tar dest=/opt/airgap-bundle/container-images/" \
		-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | grep -E 'changed|ok'
	@ansible -i $(INVENTORY) rhel-target -m copy \
		-a "src=$(BUNDLE)/binaries/docker-compose-linux-x86_64 dest=/opt/airgap-bundle/binaries/ mode=0755" \
		-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | grep -E 'changed|ok'
	@ansible -i $(INVENTORY) rhel-target -m copy \
		-a "src=$(BUNDLE)/training-materials/ansible_training_2026.tar.gz dest=/opt/airgap-bundle/training-materials/" \
		-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | grep -E 'changed|ok'
	@echo "=== checksums.sha256 → rhel-target ==="
	@ansible -i $(INVENTORY) rhel-target -m copy \
		-a "src=$(BUNDLE)/checksums.sha256 dest=/opt/airgap-bundle/checksums.sha256" \
		-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | grep -E 'changed|ok'
	@echo "=== 転送完了 ==="

transfer-win: ## Windows VM にリソースを転送
	@echo "=== Bundle → Windows ==="
	@for f in wsl.msi podman-setup.exe docker-compose-windows-x86_64.exe podman-machine-wsl.ociarchive; do \
		echo "  $$f..."; \
		ansible -i $(INVENTORY) win-airgap-vm -m ansible.windows.win_copy \
			-a "src=$(BUNDLE)/binaries/$$f dest=C:/airgap-bundle/$$f" 2>&1 | grep -E 'changed|ok'; \
	done
	@ansible -i $(INVENTORY) win-airgap-vm -m ansible.windows.win_file \
		-a 'path=C:\airgap-bundle\container-images state=directory' 2>&1 | tail -1
	@for f in training-controller.tar training-linux-node.tar; do \
		echo "  $$f..."; \
		ansible -i $(INVENTORY) win-airgap-vm -m ansible.windows.win_copy \
			-a "src=$(BUNDLE)/container-images/$$f dest=C:/airgap-bundle/container-images/$$f" 2>&1 | grep -E 'changed|ok'; \
	done
	@ansible -i $(INVENTORY) win-airgap-vm -m ansible.windows.win_file \
		-a 'path=C:\airgap-bundle\training-materials state=directory' 2>&1 | tail -1
	@ansible -i $(INVENTORY) win-airgap-vm -m ansible.windows.win_copy \
		-a "src=$(BUNDLE)/training-materials/ansible_training_2026.tar.gz dest=C:/airgap-bundle/training-materials/ansible_training_2026.tar.gz" \
		2>&1 | grep -E 'changed|ok'
	@echo "=== 転送完了 ==="

# --- デプロイ ---

deploy-repo: ## リポジトリサーバーをセットアップ
	ansible-playbook -i $(INVENTORY) playbooks/repo-server-setup.yml \
		-e "ansible_ssh_common_args='$(SSH_EXTRA)'"

deploy-rhel: deploy-repo ## RHEL 研修環境をセットアップ
	ansible-playbook -i $(INVENTORY) playbooks/rhel-setup.yml \
		-e "ansible_ssh_common_args='$(SSH_EXTRA)'"

deploy-win: ## Windows 研修環境をセットアップ
	ansible-playbook -i $(INVENTORY) playbooks/windows-setup.yml

deploy-all: deploy-rhel deploy-win ## 全環境をセットアップ

# --- 検証 ---

verify-airgap: ## airgap 状態を検証
	@echo "=== Airgap 検証 ==="
	@echo -n "  repo-server:  "; \
		ansible -i $(INVENTORY) repo-server -m command -a 'ping -c1 -W2 8.8.8.8' \
			-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | grep -q 'unreachable\|FAILED' \
			&& echo "✓ AIRGAP (インターネット到達不可)" \
			|| echo "✗ NOT AIRGAP (インターネットに到達可能 — 隔離されていません)"
	@echo -n "  rhel-target:  "; \
		ansible -i $(INVENTORY) rhel-target -m command -a 'ping -c1 -W2 8.8.8.8' \
			-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | grep -q 'unreachable\|FAILED' \
			&& echo "✓ AIRGAP (インターネット到達不可)" \
			|| echo "✗ NOT AIRGAP (インターネットに到達可能 — 隔離されていません)"
	@echo -n "  win11-airgap: "; \
		ansible -i $(INVENTORY) win-airgap-vm -m ansible.windows.win_shell \
			-a 'ping -n 1 -w 2000 8.8.8.8 | Select-String "loss"' 2>&1 | grep -q '100%' \
			&& echo "✓ AIRGAP (インターネット到達不可)" \
			|| echo "✗ NOT AIRGAP (インターネットに到達可能 — 隔離されていません)"

verify-rhel: ## RHEL 研修環境の動作確認
	@echo "=== RHEL 研修環境検証 ==="
	@ansible -i $(INVENTORY) rhel-target -m shell \
		-a 'podman exec controller ansible all -i "node1,node2,node3,lb," -m ping --user root --extra-vars "ansible_password=password ansible_ssh_common_args='\''-o StrictHostKeyChecking=no'\''"' \
		-e "ansible_ssh_common_args='$(SSH_EXTRA)'" 2>&1 | grep -E 'SUCCESS|FAILED'

verify-win: ## Windows 研修環境の動作確認
	@echo "=== Windows 研修環境検証 ==="
	ansible-playbook -i $(INVENTORY) playbooks/verify.yml --limit windows

# --- 一括操作 ---

test: verify-airgap verify-rhel ## airgap + RHEL 環境の検証

clean: destroy-vms ## 全 VM を削除してクリーン状態に
	@echo "Clean complete"

full-test: clean setup-vms transfer-rhel transfer-win deploy-all test verify-win ## フルテスト（削除→作成→デプロイ→検証）
	@echo "=== Full test complete ==="
