// native FFI 声明（native_stubs.c 的 MoonBit 面；仅 native/llvm 后端）
// wasm/js 后端走 stub.ffi.mbt（CLI 不发布到这些后端——防 moon check 全后端红）

///|
#cfg(target="native")
extern "C" fn jsonmbt_read_stdin() -> Bytes = "jsonmbt_read_stdin"

///|
#cfg(target="native")
#borrow(data)
extern "C" fn jsonmbt_write_stderr(data : Bytes, len : Int32) -> Unit = "jsonmbt_write_stderr"

///|
#cfg(target="native")
#borrow(from, to)
extern "C" fn jsonmbt_rename(
  from : Bytes,
  from_len : Int32,
  to : Bytes,
  to_len : Int32,
) -> Int32 = "jsonmbt_rename"

///|
#cfg(target="native")
#borrow(data)
extern "C" fn jsonmbt_write_stdout(data : Bytes, len : Int32) -> Unit = "jsonmbt_write_stdout"

///|
#cfg(target="native")
#borrow(cmd)
extern "C" fn jsonmbt_run_cmd(cmd : Bytes, len : Int32) -> Int32 = "jsonmbt_run_cmd"

///|
#cfg(target="native")
extern "C" fn jsonmbt_is_windows() -> Int32 = "jsonmbt_is_windows"
