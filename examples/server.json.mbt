///|
pub struct Server {
  port : Int32
  host : String
  tags : Array[String]
  retries : Int32?
}

///|
pub let server : Server = Server::{
  port: 8080,
  host: "localhost",
  tags: ["a", "b"],
  retries: None,
}
