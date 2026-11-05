module clip

import encoding.base64
import os

// copy 把文本复制到系统剪贴板，同时写入 OSC 52 转义序列以支持终端剪贴板。
pub fn copy(text string) bool {
	mut success := false

	$if macos {
		success = copy_macos(text)
	} $else $if windows {
		success = copy_windows(text)
	} $else {
		success = copy_linux(text)
	}

	// 补充写入 OSC 52 终端剪贴板转义序列（兼容 SSH 远端、tmux 以及现代终端）
	osc52 := osc52_sequence(text)
	print(osc52)

	return success
}

// osc52_sequence 生成 OSC 52 终端剪贴板转义序列。
pub fn osc52_sequence(text string) string {
	encoded := base64.encode_str(text)
	return '\x1b]52;c;${encoded}\x07'
}

fn copy_macos(text string) bool {
	mut p := os.new_process('/usr/bin/pbcopy')
	p.set_redirect_stdio()
	p.run()
	if p.status == .running {
		p.stdin_write(text)
		p.close()
		return true
	}
	return false
}

fn copy_windows(text string) bool {
	mut p := os.new_process('clip.exe')
	p.set_redirect_stdio()
	p.run()
	if p.status == .running {
		p.stdin_write(text)
		p.close()
		return true
	}
	return false
}

fn copy_linux(text string) bool {
	tools := ['wl-copy', 'xclip', 'xsel']
	for tool in tools {
		if os.exists_in_system_path(tool) {
			mut p := os.new_process(tool)
			if tool == 'xclip' {
				p.set_args(['-selection', 'clipboard'])
			} else if tool == 'xsel' {
				p.set_args(['--clipboard', '--input'])
			}
			p.set_redirect_stdio()
			p.run()
			if p.status == .running {
				p.stdin_write(text)
				p.close()
				return true
			}
		}
	}
	return false
}
