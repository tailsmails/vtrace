import os

struct FnSignature {
	name string
	receiver_interpolation string
	interpolations []string
	chan_params []string
}

struct LineWithMeta {
	text string
	original_line_num int
}

fn parse_fn_signature(line string) FnSignature {
	trimmed := line.trim_space()
	mut s := trimmed
	if s.starts_with('pub ') {
		s = s.substr(4, s.len).trim_space()
	}
	if !s.starts_with('fn ') {
		return FnSignature{}
	}
	s = s.substr(3, s.len).trim_space()

	mut receiver := ''
	mut receiver_type := ''
	mut receiver_is_shared := false
	if s.starts_with('(') {
		end_receiver := s.index(')') or { -1 }
		if end_receiver > 0 {
			mut rec_part := s.substr(1, end_receiver).trim_space()
			if rec_part.starts_with('mut ') {
				rec_part = rec_part.substr(4, rec_part.len).trim_space()
			} else if rec_part.starts_with('shared ') {
				rec_part = rec_part.substr(7, rec_part.len).trim_space()
				receiver_is_shared = true
			}
			rec_parts := rec_part.split(' ')
			if rec_parts.len > 1 {
				receiver = rec_parts[0].trim_space()
				receiver_type = rec_parts[1..].join(' ').trim_space()
			} else if rec_parts.len > 0 {
				receiver = rec_parts[0].trim_space()
			}
			s = s.substr(end_receiver + 1, s.len).trim_space()
		}
	}

	paren_start := s.index('(') or { -1 }
	if paren_start == -1 {
		return FnSignature{}
	}
	name := s.substr(0, paren_start).trim_space()

	paren_end := s.index(')') or { -1 }
	if paren_end == -1 || paren_end <= paren_start {
		return FnSignature{}
	}
	params_part := s.substr(paren_start + 1, paren_end).trim_space()

	mut interpolations := []string{}
	mut chan_params := []string{}
	
	if params_part.len > 0 {
		raw_params := params_part.split(',')
		for p in raw_params {
			p_trimmed := p.trim_space()
			mut clean_p := p_trimmed
			
			mut is_shared := false
			if clean_p.starts_with('mut ') {
				clean_p = clean_p.substr(4, clean_p.len).trim_space()
			} else if clean_p.starts_with('shared ') {
				clean_p = clean_p.substr(7, clean_p.len).trim_space()
				is_shared = true
			}
			
			parts_p := clean_p.split(' ')
			if parts_p.len > 0 {
				param_name := parts_p[0].trim_space()
				mut param_type := ''
				if parts_p.len > 1 {
					param_type = parts_p[1..].join(' ').trim_space()
				}
				
				if param_name.len > 0 && param_name != 'mut' && param_name != 'shared' {
					if is_shared {
						interpolations << param_name + ' = [shared]'
					} else if param_type.contains('chan ') || param_type.starts_with('chan ') {
						interpolations << param_name + ' = [chan]'
						chan_params << param_name
					} else {
						is_basic := param_type in ['int', 'string', 'bool', 'f32', 'f64', 'i8', 'i16', 'i32', 'i64', 'u16', 'u32', 'u64', 'byte', 'char', 'rune', 'size_t']
						if is_basic {
							interpolations << param_name + ' = \${' + param_name + '}'
						} else {
							interpolations << param_name + ' = [' + param_type + ']'
						}
					}
				}
			}
		}
	}

	mut receiver_interpolation := ''
	if receiver != '' {
		if receiver_is_shared {
			receiver_interpolation = receiver + ' = [shared]'
		} else {
			is_basic := receiver_type in ['int', 'string', 'bool', 'f32', 'f64', 'i8', 'i16', 'i32', 'i64', 'u16', 'u32', 'u64', 'byte', 'char', 'rune', 'size_t']
			if is_basic {
				receiver_interpolation = receiver + ' = \${' + receiver + '}'
			} else {
				receiver_interpolation = receiver + ' = [' + receiver_type + ']'
			}
		}
	}

	return FnSignature{
		name: name
		receiver_interpolation: receiver_interpolation
		interpolations: interpolations
		chan_params: chan_params
	}
}

fn is_block_start(line string, in_match bool) bool {
	keywords := ['if', 'for', 'match', 'else', 'fn', 'struct', 'interface', 'enum', 'union', 'unsafe', 'lock', 'rlock', 'select']
	for kw in keywords {
		if line.starts_with(kw + ' ') || line.starts_with(kw + '{') || line.starts_with(kw + '(') || line == kw {
			return true
		}
	}
	if in_match && line.ends_with('{') {
		if !line.contains(':=') && !line.contains('=') && !line.contains('return') {
			return true
		}
	}
	return false
}

fn is_fn_decl(line string) bool {
	if !line.starts_with('fn ') && !line.starts_with('pub fn ') {
		return false
	}
	if line.contains('fn C.') || line.contains('pub fn C.') || line.contains('fn JS.') || line.contains('pub fn JS.') {
		return false
	}
	return true
}

fn get_indentation(line string) string {
	mut indent := ''
	for c in line {
		if c == ` ` || c == `\t` {
			indent += c.ascii_str()
		} else {
			break
		}
	}
	return indent
}

fn count_braces_outside_strings(line string, in_single_quote bool, in_double_quote bool) (int, int, bool, bool) {
	mut open := 0
	mut close := 0
	mut single := in_single_quote
	mut double := in_double_quote
	mut is_escaped := false

	for i := 0; i < line.len; i++ {
		c := line[i]
		if is_escaped {
			is_escaped = false
			continue
		}
		if c == 92 {
			is_escaped = true
			continue
		}
		if c == 39 && !double {
			single = !single
			continue
		}
		if c == 34 && !single {
			double = !double
		}
		if !single && !double {
			if c == 123 {
				open++
			} else if c == 125 {
				close++
			}
		}
	}
	return open, close, single, double
}

fn is_valid_lhs(s string) bool {
	if s.len == 0 {
		return false
	}
	if s == '_' || s.trim_space() == '_' {
		return false
	}
	invalid_keywords := ['if', 'for', 'return', 'fn', 'import', 'const', 'struct', 'module', 'mut', 'pub']
	if s in invalid_keywords {
		return false
	}
	first := s[0]
	if !((first >= `a` && first <= `z`) || (first >= `A` && first <= `Z`) || first == `_`) {
		return false
	}
	for i := 0; i < s.len; i++ {
		c := s[i]
		is_alphanumeric := (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`)
		is_allowed_special := c == `_` || c == `.` || c == ` `
		if !is_alphanumeric && !is_allowed_special {
			return false
		}
	}
	return true
}

fn extract_assigned_vars(line string) []string {
	trimmed := line.trim_space()
	
	if trimmed.ends_with('{') {
		return []string{}
	}

	operators_to_check := [':=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>=', '=', '<<']
	for op in operators_to_check {
		if trimmed.ends_with(op) {
			return []string{}
		}
	}

	if trimmed.contains(':=') {
		parts := trimmed.split(':=')
		if parts.len > 0 {
			lhs := parts[0].trim_space()
			mut clean_lhs := lhs
			if clean_lhs.starts_with('mut ') {
				clean_lhs = clean_lhs.substr(4, clean_lhs.len).trim_space()
			}
			if clean_lhs.starts_with('shared ') {
				clean_lhs = clean_lhs.substr(7, clean_lhs.len).trim_space()
			}
			vars := clean_lhs.split(',')
			mut result := []string{}
			for v in vars {
				v_trimmed := v.trim_space()
				if is_valid_lhs(v_trimmed) {
					result << v_trimmed
				}
			}
			return result
		}
	}

	operators := ['+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>=', '=']
	for op in operators {
		if trimmed.contains(op) {
			if op == '=' {
				if trimmed.contains('==') || trimmed.contains('!=') || trimmed.contains('<=') || trimmed.contains('>=') {
					continue
				}
			}
			parts := trimmed.split(op)
			if parts.len > 0 {
				lhs := parts[0].trim_space()
				mut clean_lhs := lhs
				if clean_lhs.starts_with('mut ') {
					clean_lhs = clean_lhs.substr(4, clean_lhs.len).trim_space()
				}
				vars := clean_lhs.split(',')
				mut result := []string{}
				for v in vars {
					v_trimmed := v.trim_space()
					if is_valid_lhs(v_trimmed) {
						result << v_trimmed
					}
				}
				return result
			}
		}
	}

	if trimmed.contains('<<') && !trimmed.contains('<<=') {
		parts := trimmed.split('<<')
		if parts.len > 0 {
			mut lhs := parts[0].trim_space()
			if lhs.starts_with('mut ') {
				lhs = lhs.substr(4, lhs.len).trim_space()
			}
			if is_valid_lhs(lhs) {
				return [lhs]
			}
		}
	}

	if trimmed.ends_with('++') {
		v := trimmed.substr(0, trimmed.len - 2).trim_space()
		if is_valid_lhs(v) {
			return [v]
		}
	}
	if trimmed.ends_with('--') {
		v := trimmed.substr(0, trimmed.len - 2).trim_space()
		if is_valid_lhs(v) {
			return [v]
		}
	}

	return []string{}
}

fn rewrite_prints(line string, file_path string, fn_name string, line_num int, brace_count int) string {
	mut s := line
	mut result := ''
	mut i := 0
	for i < s.len {
		if i + 8 <= s.len && s.substr(i, i + 8) == 'println(' {
			mut is_valid_boundary := false
			if i == 0 {
				is_valid_boundary = true
			} else {
				prev := s[i - 1]
				is_valid_boundary = !((prev >= `a` && prev <= `z`) || (prev >= `A` && prev <= `Z`) || (prev >= `0` && prev <= `9`) || prev == `_`)
			}
			if is_valid_boundary {
				result += 'vtrace_println(\'' + file_path + '\', \'' + fn_name + '\', ' + line_num.str() + ', ' + brace_count.str() + ', '
				i += 8
				continue
			}
		}
		if i + 6 <= s.len && s.substr(i, i + 6) == 'print(' {
			mut is_valid_boundary := false
			if i == 0 {
				is_valid_boundary = true
			} else {
				prev := s[i - 1]
				is_valid_boundary = !((prev >= `a` && prev <= `z`) || (prev >= `A` && prev <= `Z`) || (prev >= `0` && prev <= `9`) || prev == `_`)
			}
			if is_valid_boundary {
				result += 'vtrace_print(\'' + file_path + '\', \'' + fn_name + '\', ' + line_num.str() + ', ' + brace_count.str() + ', '
				i += 6
				continue
			}
		}
		result += s[i].ascii_str()
		i++
	}
	return result
}

fn escape_quotes(s string) string {
	return s.replace('\\', '\\\\').replace('\'', '\\\'')
}

fn find_module_name(dir_path string) string {
	files := os.ls(dir_path) or { return 'main' }
	for file in files {
		if file.ends_with('.v') && file != 'vtrace_helpers.v' {
			lines := os.read_lines(os.join_path(dir_path, file)) or { continue }
			for line in lines {
				trimmed := line.trim_space()
				if trimmed.starts_with('module ') {
					parts := trimmed.split(' ')
					if parts.len > 1 {
						return parts[1].trim_space()
					}
				}
			}
		}
	}
	return 'main'
}

fn find_module_name_of_file(file_path string) string {
	lines := os.read_lines(file_path) or { return 'main' }
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('module ') {
			parts := trimmed.split(' ')
			if parts.len > 1 {
				return parts[1].trim_space()
			}
		}
	}
	return 'main'
}

fn get_helpers_content(mod_name string, use_color bool, log_file string, silent bool) string {
	color_str := use_color.str()
	silent_str := silent.str()
	escaped_log_file := log_file.replace('\\', '\\\\').replace('\'', '\\\'')
	return 'module ${mod_name}

import time
import sync
import os
import term

__global (
	vtrace_mutex sync.Mutex
)

fn init() {
	vtrace_mutex.init()
}

const vtrace_color = ${color_str}
const vtrace_silent = ${silent_str}
const vtrace_log_file = \'${escaped_log_file}\'

fn vtrace_output(text string, is_ln bool) {
	if !vtrace_silent {
		if is_ln {
			eprintln(text)
		} else {
			eprint(text)
		}
	}
	if vtrace_log_file.len > 0 {
		clean_text := term.strip_ansi(text)
		mut f := os.open_append(vtrace_log_file) or { return }
		if is_ln {
			f.writeln(clean_text) or {}
		} else {
			f.write_string(clean_text) or {}
		}
		f.close()
	}
}

pub fn vtrace_enter(call_info string) {
	vtrace_mutex.@lock()
	mut text := "┌── Entering " + call_info
	if vtrace_color {
		text = "\\x1b[2m┌──\\x1b[0m \\x1b[33mEntering " + call_info + "\\x1b[0m"
	}
	vtrace_output(text, true)
	vtrace_mutex.unlock()
}

pub fn vtrace_log(file string, fn_name string, line int, depth int, elapsed u64, extra string) {
	vtrace_mutex.@lock()
	mut prefix := ""
	if depth > 0 {
		for _ in 0 .. depth {
			prefix += "│  "
		}
	}
	prefix += "├── "

	mut time_str := ""
	if elapsed < 1000 {
		time_str = "\${elapsed} ns"
	} else if elapsed < 1000000 {
		time_str = "\${f64(elapsed) / 1000.0:.3f} μs"
	} else {
		time_str = "\${f64(elapsed) / 1000000.0:.3f} ms"
	}

	t_now := time.now().format_ss_milli()
	clock := t_now.substr(11, t_now.len)

	if vtrace_color {
		colored_prefix := "\\x1b[2m" + prefix + "\\x1b[0m"
		colored_fn := "\\x1b[33m[" + fn_name + "]\\x1b[0m"
		colored_clock := "\\x1b[90m[" + clock + "]\\x1b[0m"
		colored_file_line := "\\x1b[36m" + file + ":" + line.str() + "\\x1b[0m"
		colored_time := "\\x1b[32m(" + time_str + ")\\x1b[0m"
		
		if extra.len > 0 {
			colored_extra := "-> \\x1b[35m" + extra + "\\x1b[0m"
			vtrace_output(colored_prefix + colored_fn + " " + colored_clock + " " + colored_file_line + " " + colored_time + " " + colored_extra, true)
		} else {
			vtrace_output(colored_prefix + colored_fn + " " + colored_clock + " " + colored_file_line + " " + colored_time, true)
		}
	} else {
		if extra.len > 0 {
			vtrace_output(prefix + "[" + fn_name + "] [" + clock + "] " + file + ":" + line.str() + " (" + time_str + ") -> " + extra, true)
		} else {
			vtrace_output(prefix + "[" + fn_name + "] [" + clock + "] " + file + ":" + line.str() + " (" + time_str + ")", true)
		}
	}
	vtrace_mutex.unlock()
}

pub fn vtrace_println[T](file string, fn_name string, line int, depth int, val T) {
	_ = file
	_ = line
	vtrace_mutex.@lock()
	mut prefix := ""
	if depth > 0 {
		for _ in 0 .. depth {
			prefix += "│  "
		}
	}
	prefix += "├── "

	t_now := time.now().format_ss_milli()
	clock := t_now.substr(11, t_now.len)

	if vtrace_color {
		colored_prefix := "\\x1b[2m" + prefix + "\\x1b[0m"
		colored_fn := "\\x1b[33m[" + fn_name + "]\\x1b[0m"
		colored_clock := "\\x1b[90m[" + clock + "]\\x1b[0m"
		vtrace_output(colored_prefix + colored_fn + " " + colored_clock + " \\x1b[1m\${val}\\x1b[0m", true)
	} else {
		vtrace_output(prefix + "[" + fn_name + "] [" + clock + "] \${val}", true)
	}
	vtrace_mutex.unlock()
}

pub fn vtrace_print[T](file string, fn_name string, line int, depth int, val T) {
	_ = file
	_ = line
	vtrace_mutex.@lock()
	mut prefix := ""
	if depth > 0 {
		for _ in 0 .. depth {
			prefix += "│  "
		}
	}
	prefix += "├── "

	t_now := time.now().format_ss_milli()
	clock := t_now.substr(11, t_now.len)

	if vtrace_color {
		colored_prefix := "\\x1b[2m" + prefix + "\\x1b[0m"
		colored_fn := "\\x1b[33m[" + fn_name + "]\\x1b[0m"
		colored_clock := "\\x1b[90m[" + clock + "]\\x1b[0m"
		vtrace_output(colored_prefix + colored_fn + " " + colored_clock + " \\x1b[1m\${val}\\x1b[0m", false)
	} else {
		vtrace_output(prefix + "[" + fn_name + "] [" + clock + "] \${val}", false)
	}
	vtrace_mutex.unlock()
}
'
}

fn write_helpers_file(path string, mod_name string, use_color bool, log_file string, silent bool) ! {
	content := get_helpers_content(mod_name, use_color, log_file, silent)
	os.write_file(path, content) or { return err }
}

fn instrument_file(src_path string, dest_path string, use_color bool, auto_confirm bool) ! {
	_ := use_color
	if auto_confirm {
		os.execute('v fmt -w "' + src_path + '"')
	}
	os.cp(src_path, dest_path) or { return err }
	os.execute('v fmt -w "' + dest_path + '"')
	lines := os.read_lines(dest_path) or { return err }
	file_path := os.file_name(src_path)

	mut final_lines := []LineWithMeta{}
	for i, line in lines {
		final_lines << LineWithMeta{
			text: line
			original_line_num: i + 1
		}
	}

	mut has_time_import := false
	mut has_module_decl := false
	for line_meta in final_lines {
		trimmed_line := line_meta.text.trim_space()
		if trimmed_line.starts_with('import time') {
			has_time_import = true
		}
		if trimmed_line.starts_with('module ') {
			has_module_decl = true
		}
	}

	mut output_lines := []string{}
	mut time_imported := has_time_import

	if !has_module_decl && !time_imported {
		output_lines << 'import time'
		time_imported = true
	}

	mut is_in_fn := false
	mut brace_count := 0
	mut init_depth := 0
	mut in_multiline_comment := false
	mut current_fn_name := ''
	mut match_brace_level := 0
	
	mut in_single_quote_global := false
	mut in_double_quote_global := false

	mut local_chan_vars := []string{}

	for line_meta in final_lines {
		line := line_meta.text
		line_num := line_meta.original_line_num

		mut clean_line := line
		if clean_line.contains('//') {
			idx := clean_line.index('//') or { -1 }
			if idx >= 0 {
				clean_line = clean_line.substr(0, idx)
			}
		}
		trimmed := clean_line.trim_space()

		if in_multiline_comment {
			output_lines << line
			if trimmed.contains('*/') {
				in_multiline_comment = false
			}
			continue
		}
		if trimmed.starts_with('/*') {
			output_lines << line
			if !trimmed.contains('*/') {
				in_multiline_comment = true
			}
			continue
		}

		was_in_string := in_single_quote_global || in_double_quote_global

		num_open, num_close, new_single, new_double := count_braces_outside_strings(trimmed, in_single_quote_global, in_double_quote_global)
		in_single_quote_global = new_single
		in_double_quote_global = new_double
		
		is_in_string := was_in_string || in_single_quote_global || in_double_quote_global

		if is_fn_decl(trimmed) {
			is_in_fn = true
			output_lines << line

			sig := parse_fn_signature(trimmed)
			current_fn_name = sig.name

			mut param_interpolations := []string{}
			if sig.receiver_interpolation != '' {
				param_interpolations << sig.receiver_interpolation
			}
			for interp in sig.interpolations {
				param_interpolations << interp
			}
			mut call_info := sig.name + '()'
			if param_interpolations.len > 0 {
				call_info = sig.name + '(' + param_interpolations.join(', ') + ')'
			}

			indentation := get_indentation(line) + '\t'
			output_lines << indentation + 'mut vtrace_t := time.sys_mono_now()'
			output_lines << indentation + '_ = vtrace_t'
			output_lines << indentation + "vtrace_enter('" + escape_quotes(call_info) + "')"

			brace_count += (num_open - num_close)
			continue
		}

		net_braces := num_open - num_close

		is_block := is_block_start(trimmed, match_brace_level > 0)

		mut insert_after := false

		if is_in_fn && init_depth == 0 && !is_in_string {
			if trimmed != '' && 
			   !trimmed.starts_with('//') && 
			   !trimmed.starts_with('}') && 
			   !trimmed.starts_with('else') && 
			   !trimmed.starts_with('or') && 
			   !trimmed.starts_with('case') && 
			   !trimmed.starts_with('default:') && 
			   !trimmed.starts_with('const') && 
			   !trimmed.starts_with('struct') && 
			   !trimmed.starts_with('interface') && 
			   !trimmed.starts_with('enum') && 
			   !trimmed.starts_with('union') && 
			   !trimmed.starts_with('import') && 
			   !trimmed.starts_with('module') && 
			   !trimmed.starts_with('@[') && 
			   !is_fn_decl(trimmed) {
				
				if !is_block_start(trimmed, match_brace_level > 0) && !trimmed.starts_with('return') && !trimmed.ends_with('{') {
					if !trimmed.contains('print(') && !trimmed.contains('println(') {
						if trimmed != 'continue' && trimmed != 'break' && !trimmed.starts_with('continue ') && !trimmed.starts_with('break ') {
							if match_brace_level == 0 || brace_count > match_brace_level {
								insert_after = true
							}
						}
					}
				}
			}
		}

		if is_in_fn {
			if is_block {
				brace_count += net_braces
			} else {
				if net_braces > 0 {
					init_depth += net_braces
				} else if net_braces < 0 {
					if init_depth > 0 {
						init_depth += net_braces 
						if init_depth < 0 {
							brace_count += init_depth
							init_depth = 0
						}
					} else {
						brace_count += net_braces
					}
				}
			}

			if brace_count <= 0 {
				is_in_fn = false
				brace_count = 0
				init_depth = 0
			}
		}

		mut rewritten_line := line
		if is_in_fn && init_depth == 0 && !is_in_string {
			rewritten_line = rewrite_prints(rewritten_line, file_path, current_fn_name, line_num, brace_count)
		}
		output_lines << rewritten_line

		if trimmed.starts_with('module ') && !time_imported {
			output_lines << 'import time'
			time_imported = true
		}

		if insert_after {
			vars := extract_assigned_vars(trimmed)
			
			if trimmed.contains('chan ') {
				for v in vars {
					if v !in local_chan_vars {
						local_chan_vars << v
					}
				}
			}

			mut clean_vars := []string{}
			sig := parse_fn_signature(trimmed)
			for v in vars {
				if v !in local_chan_vars && v !in sig.chan_params {
					clean_vars << v
				}
			}

			mut extra_str := ''
			if clean_vars.len > 0 {
				mut var_prints := []string{}
				for v in clean_vars {
					var_prints << v + " = \${" + v + "}"
				}
				extra_str = var_prints.join(', ')
			} else {
				extra_str = escape_quotes(trimmed)
			}

			indentation := get_indentation(line)
			output_lines << indentation + "vtrace_log('" + file_path + "', '" + current_fn_name + "', " + line_num.str() + ", " + brace_count.str() + ", time.sys_mono_now() - vtrace_t, '" + extra_str + "')"
			output_lines << indentation + "vtrace_t = time.sys_mono_now()"
		}

		if match_brace_level > 0 && brace_count < match_brace_level {
			match_brace_level = 0
		}
		if trimmed.starts_with('match ') || trimmed.contains(' match ') {
			match_brace_level = brace_count
		}
	}

	os.write_file(dest_path, output_lines.join('\n')) or { return err }
}

fn instrument_single_file(src_file string, temp_dir string, use_color bool, auto_confirm bool, log_file string, silent bool) ! {
	if !os.exists(temp_dir) {
		os.mkdir_all(temp_dir) or { return err }
	}
	file_name := os.file_name(src_file)
	dest_file := os.join_path(temp_dir, file_name)
	instrument_file(src_file, dest_file, use_color, auto_confirm)!

	src_dir := os.dir(src_file)
	mut resolved_src_dir := src_dir
	if resolved_src_dir == '' {
		resolved_src_dir = '.'
	}
	current_exec := os.file_name(os.executable())
	files := os.ls(resolved_src_dir) or { return err }
	for file in files {
		if file == current_exec {
			continue
		}
		src_path := os.join_path(resolved_src_dir, file)
		if !os.is_dir(src_path) && !file.ends_with('.v') {
			dest_path := os.join_path(temp_dir, file)
			os.cp(src_path, dest_path) or { return err }
		}
	}

	mod_name := find_module_name_of_file(src_file)
	helpers_path := os.join_path(temp_dir, 'vtrace_helpers.v')
	write_helpers_file(helpers_path, mod_name, use_color, log_file, silent)!
}

fn walk_and_instrument(src string, dest string, use_color bool, auto_confirm bool, log_file string, silent bool) ! {
	current_exec := os.file_name(os.executable())
	current_exec_source := current_exec.replace('.exe', '') + '.v'
	walk_and_instrument_internal(src, dest, use_color, auto_confirm, log_file, silent, current_exec, current_exec_source)!
}

fn walk_and_instrument_internal(src string, dest string, use_color bool, auto_confirm bool, log_file string, silent bool, current_exec string, current_exec_source string) ! {
	if !os.exists(dest) {
		os.mkdir_all(dest) or { return err }
	}

	files := os.ls(src) or { return err }
	mut has_v_files := false

	for file in files {
		src_path := os.join_path(src, file)
		dest_path := os.join_path(dest, file)
		
		if os.is_dir(src_path) {
			if file == '.vtrace_temp' {
				continue
			}
			walk_and_instrument_internal(src_path, dest_path, use_color, auto_confirm, log_file, silent, current_exec, current_exec_source)!
		} else {
			if file == current_exec || file == current_exec_source {
				continue
			}
			if file.ends_with('.v') {
				has_v_files = true
				instrument_file(src_path, dest_path, use_color, auto_confirm)!
			} else {
				os.cp(src_path, dest_path) or { return err }
			}
		}
	}

	if has_v_files {
		mod_name := find_module_name(src)
		helpers_path := os.join_path(dest, 'vtrace_helpers.v')
		write_helpers_file(helpers_path, mod_name, use_color, log_file, silent)!
	}
}

fn generate_self_contained_vt_v(instrumented_file_path string, output_path string, use_color bool, log_file string, silent bool) ! {
	lines := os.read_lines(instrumented_file_path) or { return err }
	mut out_lines := []string{}
	mut inserted_imports := false

	mut has_sync := false
	mut has_time := false
	mut has_os := false
	mut has_term := false
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('import ') {
			parts := trimmed.split(' ')
			if parts.len > 1 {
				mod := parts[1].trim_space()
				if mod == 'sync' {
					has_sync = true
				} else if mod == 'time' {
					has_time = true
				} else if mod == 'os' {
					has_os = true
				} else if mod == 'term' {
					has_term = true
				}
			}
		}
	}

	for line in lines {
		trimmed := line.trim_space()
		out_lines << line
		if trimmed.starts_with('module ') {
			if !has_sync {
				out_lines << 'import sync'
				has_sync = true
			}
			if !has_time {
				out_lines << 'import time'
				has_time = true
			}
			if !has_os {
				out_lines << 'import os'
				has_os = true
			}
			if !has_term {
				out_lines << 'import term'
				has_term = true
			}
			inserted_imports = true
		}
	}

	if !inserted_imports {
		mut prepended := []string{}
		if !has_sync {
			prepended << 'import sync'
		}
		if !has_time {
			prepended << 'import time'
		}
		if !has_os {
			prepended << 'import os'
		}
		if !has_term {
			prepended << 'import term'
		}
		for line in out_lines {
			prepended << line
		}
		out_lines = prepended.clone()
	}

	helpers_content_raw := get_helpers_content('', use_color, log_file, silent)
	idx := helpers_content_raw.index('\n') or { 0 }
	helpers_content := helpers_content_raw.substr(idx + 1, helpers_content_raw.len)

	out_lines << helpers_content
	os.write_file(output_path, out_lines.join('\n')) or { return err }
}

fn has_main_fn(dir_path string) bool {
	files := os.ls(dir_path) or { return false }
	for file in files {
		if file.ends_with('.v') && file != 'vtrace_helpers.v' {
			lines := os.read_lines(os.join_path(dir_path, file)) or { continue }
			for line in lines {
				trimmed := line.trim_space()
				if trimmed.starts_with('fn main(') || trimmed.starts_with('pub fn main(') || trimmed.starts_with('fn main ') || trimmed.starts_with('pub fn main ') {
					return true
				}
			}
		}
	}
	return false
}

fn main() {
	if os.args.len < 2 {
		println('Usage: vtrace [-bw] [-c] [-y] [-s <log_file>] [-ss <log_file>] <file_or_directory> [compiler_flags] [-- program_arguments]')
		return
	}

	mut use_color := true
	mut only_compile := false
	mut auto_confirm := false
	mut silent_mode := false
	mut log_file_path := ''
	mut file_index := 1

	for file_index < os.args.len {
		arg := os.args[file_index]
		if arg == '-bw' {
			use_color = false
			file_index++
		} else if arg == '-c' {
			only_compile = true
			file_index++
		} else if arg == '-y' {
			auto_confirm = true
			file_index++
		} else if arg == '-s' {
			if file_index + 1 >= os.args.len {
				println('Error: -s requires a log file path.')
				return
			}
			log_file_path = os.args[file_index + 1]
			silent_mode = false
			file_index += 2
		} else if arg == '-ss' {
			if file_index + 1 >= os.args.len {
				println('Error: -ss requires a log file path.')
				return
			}
			log_file_path = os.args[file_index + 1]
			silent_mode = true
			file_index += 2
		} else {
			break
		}
	}

	if file_index >= os.args.len {
		println('Usage: vtrace [-bw] [-c] [-y] [-s <log_file>] [-ss <log_file>] <file_or_directory> [compiler_flags] [-- program_arguments]')
		return
	}

	target_path := os.args[file_index]
	if !os.exists(target_path) {
		println('Error: Path "${target_path}" does not exist.')
		return
	}

	mut absolute_log_path := ''
	if log_file_path.len > 0 {
		if os.is_abs_path(log_file_path) {
			absolute_log_path = log_file_path
		} else {
			absolute_log_path = os.join_path(os.getwd(), log_file_path)
		}
	}

	mut compiler_flags := []string{}
	mut program_args := []string{}
	mut separator_found := false

	if os.args.len > file_index + 1 {
		for arg in os.args[(file_index + 1)..] {
			if arg == '--' {
				separator_found = true
				continue
			}
			if separator_found {
				program_args << arg
			} else {
				compiler_flags << arg
			}
		}
	}

	mut src_dir := ''
	is_dir := os.is_dir(target_path)

	if is_dir {
		src_dir = target_path
	} else {
		src_dir = os.dir(target_path)
		if src_dir == '' {
			src_dir = '.'
		}
	}

	mut program_name := ''
	mut target_file_name := ''
	if is_dir {
		program_name = os.file_name(os.real_path(target_path))
		if program_name == '' || program_name == '.' {
			program_name = 'program'
		}
	} else {
		target_file_name = os.file_name(target_path)
		program_name = target_file_name
		if target_file_name.ends_with('.v') {
			program_name = target_file_name.substr(0, target_file_name.len - 2)
		}
	}

	if !auto_confirm {
		ans := os.input('Do you want to format your original V files using `v fmt`? [y/N]: ').trim_space().to_lower()
		if ans == 'y' || ans == 'yes' {
			auto_confirm = true
		}
	}

	temp_dir_path := os.join_path(src_dir, '.vtrace_temp')

	if os.exists(temp_dir_path) {
		os.rmdir_all(temp_dir_path) or {}
	}

	if is_dir {
		println('Walking and instrumenting directory: ${src_dir} ...')
		walk_and_instrument(src_dir, temp_dir_path, use_color, auto_confirm, absolute_log_path, silent_mode)!
	} else {
		println('Instrumenting file: ${target_path} ...')
		instrument_single_file(target_path, temp_dir_path, use_color, auto_confirm, absolute_log_path, silent_mode)!
	}

	if !has_main_fn(temp_dir_path) {
		eprintln('Error: No `main` function found in the target program.')
		os.rmdir_all(temp_dir_path) or {}
		return
	}

	mut temp_exe := ''
	mut output_binary_name := program_name + '.vt'
	$if windows {
		output_binary_name += '.exe'
	}
	output_binary_path := os.join_path(src_dir, output_binary_name)

	if only_compile {
		temp_exe = output_binary_path
	} else {
		temp_exe = os.join_path(temp_dir_path, 'vtrace_temp_exec')
		$if windows {
			temp_exe += '.exe'
		}
	}

	mut compile_parts := ['v']
	if compiler_flags.len > 0 {
		compile_parts << compiler_flags.join(' ')
	}
	compile_parts << '-enable-globals'
	compile_parts << '-o'
	compile_parts << '"' + temp_exe + '"'
	compile_parts << '"' + temp_dir_path + '"'
	
	compile_cmd := compile_parts.join(' ')

	println('Compiling: ${compile_cmd} ...')
	compile_res := os.execute(compile_cmd)
	if compile_res.exit_code != 0 {
		eprintln('Compilation failed:')
		eprint(compile_res.output)
		os.rmdir_all(temp_dir_path) or {}
		return
	}

	if !is_dir {
		output_src_path := os.join_path(src_dir, program_name + '.vt.v')
		println('Generating self-contained trace source file: ${output_src_path} ...')
		generate_self_contained_vt_v(os.join_path(temp_dir_path, target_file_name), output_src_path, use_color, absolute_log_path, silent_mode)!
	}

	if only_compile {
		println('Traced program successfully compiled to: ${output_binary_path}')
		if !is_dir {
			output_src_path := os.join_path(src_dir, program_name + '.vt.v')
			println('Traced source code generated at: ${output_src_path}')
			println('Note: To run/compile the .vt.v file manually, always use the -enable-globals flag:')
			println('      v -enable-globals run ${output_src_path}')
		}
		os.rmdir_all(temp_dir_path) or {}
		return
	}

	mut run_parts := ['"' + temp_exe + '"']
	if program_args.len > 0 {
		for arg in program_args {
			run_parts << '"' + arg + '"'
		}
	}
	run_cmd := run_parts.join(' ')

	println('Executing: ${run_cmd}')
	println('-'.repeat(40))

	exit_code := os.system(run_cmd)

	os.rmdir_all(temp_dir_path) or {}

	if exit_code != 0 {
		exit(exit_code)
	}
}
