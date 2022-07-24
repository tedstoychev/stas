import os
import flag
import term

fn run_pipeline(filename string, mut db Debug)string{
	db.start("File")
	data := os.read_file(filename) or {
		eprintln("Cannot read file '$filename'!")
		exit(1)
	}
	db.info("Opened '$filename'")
	db.info("Read $data.len characters")
	db.end()
	db.start("Scanner")
	mut scanner := Scanner {
		text: data
		cap: data.len
		filename: filename
	}
	mut tokens := []Token{cap: 20}
	for {
		if i := scanner.scan_token() {
			tokens << i
		} else {
			db.info("EOF hit, read $tokens.len tokens")
			break
		}
	}
	if tokens.len == 0 {
		println("No readable tokens in file!")
		exit(0)
	}
	db.end()
	db.start("Parser")
	mut parser := Parser {
		s: mut scanner
		tokens: tokens
		curr: tokens[0]
		cap: tokens.len
		ctx: unsafe { nil }
	}
	for {
		parser.parse_new_func() or {
			parser.eof_cleanup()
			break
		}
	}
	db.start("Codegen")
	mut gen := Gen {
		fns: parser.fns
		s: mut scanner
	}
	gen.gen_all()
	file_out := gen.file.str()
	db.info("Wrote $file_out.len characters")
	db.end()
	return file_out
}

const githash = $embed_file('.githash')

fn main(){
	mut fp := flag.new_flag_parser(os.args)

	fp.application(os.file_name(os.args[0]))
	fp.version('0.0.1 ${githash.to_string()}')
	fp.description('Compiler for an unknown, unnamed and unheard of stack based programming language')
	fp.skip_executable()

	pref_run := fp.bool('run', `r`, false, 'run program after compiling, then deletes')
	pref_bat := fp.bool('show', `s`, false, 'open nasm assembly output in a bat process')
	mut pref_out := fp.string('', `o`, '', 'output to file (accepts *.asm, *.S, *.o, *)')
	pref_asm := if fp.bool('', `g`, false, 'compile with debug symbols') { ' -g -F stabs' } else { '' }
	pref_ver := fp.bool('version', `v`, false, fp.default_version_label)
	pref_deb := fp.bool('debug', `d`, false, 'run the compiler in debug mode')

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
	mut db := Debug{is_debug: pref_deb}
	source := run_pipeline(filename, mut db)

	pref_ext := os.file_ext(pref_out)

	db.start("Finalise")
	file_write_tmp := os.join_path_single(os.temp_dir(),get_hash_str(filename))
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
	db.info("Created assembly file on disk")

	if pref_bat {
		db.end_all()
		mut run_process := os.new_process('/usr/bin/bat')
		run_process.set_args(['-l','nasm','${file_write_tmp}.asm'])
		run_process.wait()
		os.rm('${file_write_tmp}.asm') or {}
		exit(0)
	}

	object_file_out := if pref_ext == '.o' {pref_out} else {'${file_write_tmp}.o'}
	db.info("Executing 'nasm -O0 -felf64$pref_asm -o $object_file_out ${file_write_tmp}.asm'")
	nasm_res := os.execute('nasm -O0 -felf64$pref_asm -o $object_file_out ${file_write_tmp}.asm')

	if nasm_res.exit_code != 0 {
		eprintln(term.red("NASM error, this should never happen"))
		eprintln(nasm_res.output)
		exit(1)
	}
	db.info("Assembler finished")
	if pref_ext == '.o' {
		db.end_all()
		exit(0)
	}

	if pref_out == '' {
		pref_out = 'a.out'
	} // default output
	db.info("Executing 'ld ${file_write_tmp}.o -o $pref_out'")
	os.execute_or_panic('ld ${file_write_tmp}.o -o $pref_out')
	db.info("Linker finished")

	os.rm('${file_write_tmp}.asm') or {}
	os.rm('${file_write_tmp}.o') or {}

	if pref_run {
		db.end_all()
		exefile := os.abs_path(pref_out)
		mut run_process := os.new_process(exefile)
		run_process.wait()
		ret := run_process.code
		run_process.close()
		os.rm(exefile) or {}
		exit(ret)
	} else {
		db.info("Executable '$pref_out' compiled!")
		db.end_all()
	}
}
