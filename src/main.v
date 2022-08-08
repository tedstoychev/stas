module main

import stas
import os
import flag
import term

const githash = $embed_file('.githash')

fn main(){
	mut fp := flag.new_flag_parser(os.args)

	fp.application("stas") // os.file_name(os.args[0])
	fp.version('0.0.2 ${githash.to_string()}')
	fp.description('Compiler for a stack based programming language')
	fp.skip_executable()
	pref_run := fp.bool('run', `r`, false, 'run program after compiling, then deletes')
	pref_tut := fp.bool('tutor', 0, false, 'activate tutor mode. program will stop at the checker and display information relating to the stack, used for learning the language')
	pref_bat := fp.bool('show', `s`, false, 'open nasm assembly output in a bat process')
	//pref_ir := fp.string('show_ir', 0, '', '')
	mut pref_out := fp.string('', `o`, '', 'output to file (accepts *.asm, *.S, *.o, *)')
	pref_asm := if fp.bool('', `g`, false, 'compile with debug symbols') { ' -F dwarf -g' } else { '' }
	pref_ver := fp.bool('version', `v`, false, fp.default_version_label)
	//pref_deb := fp.bool('debug', `d`, false, 'run the compiler in debug mode')

	args := fp.finalize() or {
		eprintln(err.msg())
		exit(1)
	}

	if pref_ver {
		println('$fp.application_name $fp.application_version w/ git hash ${githash.to_string()}')
		exit(0)
	}

	if args.len == 0 {
		eprintln("Must provide a file!")
		exit(1)
	} else if args.len != 1 {
		eprintln("Currently only accept single files!")
		exit(1)
	}
	filename := args[0]

	source := stas.compile_nasm(filename, pref_tut)

	pref_ext := os.file_ext(pref_out)

	file_write_tmp := os.join_path_single(os.temp_dir(),stas.get_hash_str(filename))
	if !pref_bat && pref_ext in ['.asm','.S'] {
		os.write_file(pref_out,source) or {
			panic("Failed to write file!")
		}
		exit(0)
	} else {
		os.write_file('${file_write_tmp}.asm',source) or {
			panic("Failed to write temporary file!")
		}
	}

	if pref_bat {
		mut run_process := os.new_process('/usr/bin/bat')
		run_process.set_args(['-l','nasm','${file_write_tmp}.asm'])
		run_process.wait()
		os.rm('${file_write_tmp}.asm') or {}
		exit(0)
	}

	object_file_out := if pref_ext == '.o' {pref_out} else {'${file_write_tmp}.o'}
	nasm_res := os.execute('nasm -felf64$pref_asm -o $object_file_out ${file_write_tmp}.asm')

	if nasm_res.exit_code != 0 {
		eprintln(term.red("NASM error, this should never happen"))
		eprintln(nasm_res.output)
		exit(1)
	}
	if pref_ext == '.o' {
		exit(0)
	}

	if pref_out == '' {
		pref_out = 'a.out'
	} // default output
	os.execute_or_panic('ld ${file_write_tmp}.o -o $pref_out')

	os.rm('${file_write_tmp}.asm') or {}
	os.rm('${file_write_tmp}.o') or {}

	if pref_run {
		exefile := os.abs_path(pref_out)
		mut run_process := os.new_process(exefile)
		run_process.wait()
		ret := run_process.code
		run_process.close()
		os.rm(exefile) or {}
		exit(ret)
	}
}
