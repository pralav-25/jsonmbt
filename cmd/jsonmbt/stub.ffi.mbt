// 非 native 后端的 FFI stub（CLI 实际只发布 native；此文件保 moon check 全后端绿）

///|
#cfg(not(target="native"))
fn jsonmbt_read_stdin() -> Bytes {
  abort("stdin is only available in the native build")
}

///|
#cfg(not(target="native"))
fn jsonmbt_write_stderr(data : Bytes, len : Int32) -> Unit {
  let _ = data
  let _ = len
  abort("stderr is only available in the native build")
}

///|
#cfg(not(target="native"))
fn jsonmbt_rename(
  from : Bytes,
  from_len : Int32,
  to : Bytes,
  to_len : Int32,
) -> Int32 {
  let _ = from
  let _ = from_len
  let _ = to
  let _ = to_len
  abort("rename is only available in the native build")
}

///|
#cfg(not(target="native"))
fn jsonmbt_write_stdout(data : Bytes, len : Int32) -> Unit {
  let _ = data
  let _ = len
  abort("stdout is only available in the native build")
}

///|
#cfg(not(target="native"))
fn jsonmbt_run_cmd(cmd : Bytes, len : Int32) -> Int32 {
  let _ = cmd
  let _ = len
  abort("run_cmd is only available in the native build")
}

///|
#cfg(not(target="native"))
fn jsonmbt_is_windows() -> Int32 {
  abort("platform probe is only available in the native build")
}
