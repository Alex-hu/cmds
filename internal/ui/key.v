module ui

import os
import term.termios

#include <unistd.h>

fn C.read(fd int, buf voidptr, count usize) isize

// KeyType 定义 TUI 支持的按键类别。
pub enum KeyType {
	unknown
	char
	tab
	shift_tab
	up
	down
	left
	right
	enter
	escape
	backspace
	quit
}

// KeyAction 包装按键类型与携带字符。
pub struct KeyAction {
pub:
	typ KeyType
	ch  rune
}

// TerminalRawGuard 负责进入与退出终端 Raw Mode，以及管理备用屏幕。
pub struct TerminalRawGuard {
mut:
	orig_termios termios.Termios
	active       bool
}

// enable 开启终端 Raw 模式、进入备用屏幕并隐藏光标。
pub fn (mut g TerminalRawGuard) enable() ! {
	if termios.tcgetattr(0, mut g.orig_termios) != 0 {
		return error('tcgetattr 失败')
	}
	mut raw := g.orig_termios
	raw.c_lflag &= termios.invert(termios.flag(int(C.ECHO) | int(C.ICANON) | int(C.ISIG) | int(C.IEXTEN)))
	raw.c_iflag &= termios.invert(termios.flag(int(C.IXON) | int(C.ICRNL) | int(C.BRKINT) | int(C.INPCK) | int(C.ISTRIP)))
	raw.c_cflag |= termios.flag(C.CS8)
	raw.c_cc[C.VMIN] = 1
	raw.c_cc[C.VTIME] = 0
	if termios.tcsetattr(0, C.TCSANOW, mut raw) != 0 {
		return error('tcsetattr raw 失败')
	}
	g.active = true
	// 切换到备用屏幕 (Alternate Screen) 并隐藏光标
	print('\x1b[?1049h\x1b[?25l')
	flush_stdout()
}

// disable 恢复主屏幕并复原终端原本属性。
pub fn (mut g TerminalRawGuard) disable() {
	if !g.active {
		return
	}
	// 切回主屏幕并恢复显示光标
	print('\x1b[?1049l\x1b[?25h')
	flush_stdout()
	termios.tcsetattr(0, C.TCSANOW, mut g.orig_termios)
	g.active = false
}

// read_key 从标准输入阻塞读取一次按键或 ANSI 转义序列。
pub fn read_key() KeyAction {
	mut b := u8(0)
	n := unsafe { C.read(0, &b, 1) }
	if n <= 0 {
		return KeyAction{ typ: .unknown }
	}

	match b {
		3 { // Ctrl+C
			return KeyAction{ typ: .quit }
		}
		9 { // Tab
			return KeyAction{ typ: .tab }
		}
		10, 13 { // Enter
			return KeyAction{ typ: .enter }
		}
		127, 8 { // Backspace
			return KeyAction{ typ: .backspace }
		}
		27 { // Escape 或 CSI 转义序列
			if !os.fd_is_pending(0) {
				return KeyAction{ typ: .escape }
			}
			mut b2 := u8(0)
			if unsafe { C.read(0, &b2, 1) } <= 0 {
				return KeyAction{ typ: .escape }
			}
			if b2 == `[` {
				mut b3 := u8(0)
				if unsafe { C.read(0, &b3, 1) } <= 0 {
					return KeyAction{ typ: .escape }
				}
				match b3 {
					`A` { return KeyAction{ typ: .up } }
					`B` { return KeyAction{ typ: .down } }
					`C` { return KeyAction{ typ: .right } }
					`D` { return KeyAction{ typ: .left } }
					`Z` { return KeyAction{ typ: .shift_tab } }
					`1`...`9` {
						// 类似 \x1b[5~ (PageUp), \x1b[6~ (PageDown)
						if os.fd_is_pending(0) {
							mut b4 := u8(0)
							unsafe { C.read(0, &b4, 1) }
						}
						return KeyAction{ typ: .unknown }
					}
					else {
						return KeyAction{ typ: .unknown }
					}
				}
			}
			return KeyAction{ typ: .escape }
		}
		else {
			return KeyAction{ typ: .char, ch: rune(b) }
		}
	}
}
