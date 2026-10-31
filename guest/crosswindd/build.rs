// SPDX-License-Identifier: AGPL-3.0-or-later
fn main() {
    println!("cargo:rerun-if-changed=../../proto");
    prost_build::compile_protos(&["../../proto/display.proto", "../../proto/control.proto"], &["../../proto"]).unwrap();
}
