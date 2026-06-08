/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2026 HomeProxy Custom
 */

'use strict';
'require fs';
'require rpc';
'require ui';
'require view';

const backupPath = '/tmp/homeproxy-backup.tar.gz';
const restorePath = '/tmp/homeproxy-restore.tar.gz';

const callBackupCreate = rpc.declare({
	object: 'luci.homeproxy',
	method: 'backup_create',
	expect: { '': {} }
});

const callBackupValidate = rpc.declare({
	object: 'luci.homeproxy',
	method: 'backup_validate',
	expect: { '': {} }
});

const callBackupRestore = rpc.declare({
	object: 'luci.homeproxy',
	method: 'backup_restore',
	expect: { '': {} }
});

function downloadFile(path, filename) {
	return fs.read_direct(path, 'blob').then((blob) => {
		const url = window.URL.createObjectURL(blob);
		let a = document.createElement('a');

		a.style.display = 'none';
		a.href = url;
		a.download = filename;
		document.body.appendChild(a);
		a.click();
		a.remove();
		window.URL.revokeObjectURL(url);
	});
}

function renderFileList(files) {
	if (!files || !files.length)
		return E('em', _('没有文件。'));

	return E('ul', {}, files.map((file) => E('li', {}, file)));
}

function setButtonText(btn, text) {
	if (btn && btn.firstChild)
		btn.firstChild.data = text;
}

return view.extend({
	handleCreateBackup(ev) {
		const btn = ev.currentTarget || ev.target;

		setButtonText(btn, _('正在生成备份文件...'));

		return L.resolveDefault(callBackupCreate(), {}).then((res) => {
			if (!res.result)
				throw new Error(res.error || _('生成备份文件失败。'));

			const filename = 'homeproxy-backup-%s.tar.gz'.format((new Date()).toISOString().replace(/[:.]/g, '-'));

			return downloadFile(backupPath, filename).then(() => {
				ui.addNotification(null, E('p', _('备份文件已生成并开始下载。')), 'info');
			});
		}).catch((err) => {
			ui.addNotification(null, E('p', err.message || err));
		}).finally(() => {
			setButtonText(btn, _('生成备份文件'));
		});
	},

	handleUploadRestore(ev) {
		const btn = ev.currentTarget || ev.target;

		setButtonText(btn, _('正在上传备份文件...'));

		return ui.uploadFile(restorePath).then(() => {
			setButtonText(btn, _('正在检查备份文件...'));
			return L.resolveDefault(callBackupValidate(), {});
		}).then((res) => {
			if (!res.valid)
				throw new Error(res.error || _('上传的备份文件无效。'));

			ui.showModal(_('确认恢复 HomeProxy 备份？'), [
				E('p', _('上传的备份文件包含下面这些 HomeProxy 源配置。恢复会覆盖当前 HomeProxy 设置、自定义直连/代理列表，以及已上传的证书和私钥。')),
				renderFileList(res.files),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'btn',
						'click': ui.createHandlerFn(this, () => {
							return fs.remove(restorePath).finally(ui.hideModal);
						})
					}, [ _('取消') ]),
					' ',
					E('button', {
						'class': 'btn cbi-button-action important',
						'click': ui.createHandlerFn(this, 'handleRestoreConfirm')
					}, [ _('继续') ])
				])
			]);
		}).catch((err) => {
			ui.addNotification(null, E('p', err.message || err));
			return fs.remove(restorePath).catch(() => {});
		}).finally(() => {
			setButtonText(btn, _('上传备份文件...'));
		});
	},

	handleRestoreConfirm() {
		ui.showModal(_('正在恢复 HomeProxy 备份...'), [
			E('p', { 'class': 'spinning' }, _('正在应用备份文件并重启 HomeProxy。'))
		]);

		return L.resolveDefault(callBackupRestore(), {}).then((res) => {
			if (!res.result)
				throw new Error(res.error || _('恢复失败。'));

			ui.showModal(_('恢复完成'), [
				E('p', _('HomeProxy 配置已恢复，服务已重启。')),
				E('p', _('恢复前的 HomeProxy 配置回滚包已保存到 %s。').format(res.rollback || '/tmp/homeproxy-rollback.tar.gz')),
				renderFileList(res.files),
				E('div', { 'class': 'right' },
					E('button', { 'class': 'btn', 'click': ui.hideModal }, [ _('关闭') ])
				)
			]);
		}).catch((err) => {
			ui.addNotification(null, E('p', err.message || err));
			ui.hideModal();
		});
	},

	render() {
		const readonly = !L.hasViewPermission();

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('HomeProxy 配置备份 / 恢复')),
			E('div', { 'class': 'cbi-map-descr' },
				_('导出和导入 HomeProxy 源配置，用于重装后完整恢复 WebUI 设置。')),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('备份')),
				E('div', { 'class': 'cbi-section-descr' },
					_('下载包含 /etc/config/homeproxy、自定义直连/代理列表，以及已上传证书和私钥的 tar.gz 备份文件。')),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('下载备份')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('button', {
							'class': 'btn cbi-button cbi-button-action important',
							'disabled': readonly || null,
							'click': ui.createHandlerFn(this, 'handleCreateBackup')
						}, [ _('生成备份文件') ])
					])
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('恢复')),
				E('div', { 'class': 'cbi-section-descr' },
					_('上传 HomeProxy 备份文件并覆盖当前 HomeProxy 源配置。恢复前会自动保存回滚包。')),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('恢复备份')),
					E('div', { 'class': 'cbi-value-field' }, [
						E('button', {
							'class': 'btn cbi-button cbi-button-action important',
							'disabled': readonly || null,
							'click': ui.createHandlerFn(this, 'handleUploadRestore')
						}, [ _('上传备份文件...') ])
					])
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
