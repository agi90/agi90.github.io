#!/bin/zsh

cargo build \
    --manifest-path=../gb-rust/wasm/Cargo.toml \
    --target=wasm32-unknown-unknown \
    --release

cp -r ../gb-rust/wasm/static/* gb-rust/

cp ../gb-rust/target/wasm32-unknown-unknown/release/wasm.wasm \
    gb-rust/emu.wasm

git add gb-rust

GIT_SHA=`git -C ../gb-rust rev-parse HEAD`
git commit -F- <<EOF
Import gb-rust

https://github.com/agi90/gb-rust/commit/$GIT_SHA
EOF
