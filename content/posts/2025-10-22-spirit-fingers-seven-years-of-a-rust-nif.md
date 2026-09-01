---
title: "spirit_fingers at seven: a Rust SimHash NIF"
description: "A small Rust SimHash NIF for Elixir, seven years old this week: why it's Rust, how it benchmarks against the pure-Elixir libraries, vendoring its one dependency, and what keeping a NIF alive across Rustler versions actually involves."
tags: [personal, elixir, rust, simhash, oss]
---

I cut spirit_fingers v0.5.1 an hour ago, which, with the first release back in May 2018, makes this a seven-year-old library. That's longer than I've kept almost anything alive, so it feels like a good moment to write down what a small library that does one job well actually looks like from the inside. The one job: SimHash operations for Elixir, with the hashing done in Rust.

## Why it's Rust

SimHash is a locality-sensitive hash: similar inputs give you fingerprints a small Hamming distance apart, which is exactly what you want for near-duplicate detection over a lot of text. It's in Rust for a blunt reason, which I put on the tin as "Fast SimHash NIFs written in Rust 🐇💨 as Erlang/Elixir versions were too slow 🐢".

That wasn't a dig at Elixir. Fingerprinting a short string in pure Elixir is fine. Fingerprinting whole documents, some of them megabytes, means tight bit-twiddling over large binaries, and the BEAM is not where you want to do that. Rust is, and Rustler makes the bridge tolerable. The Elixir side is barely there, just four function heads that all look like this:

```elixir
# lib/simhash.ex
@spec similarity_hash(binary()) :: {:ok, t()}
def similarity_hash(_bin), do: :erlang.nif_error(:nif_not_loaded)
```

The real work is in `native/simhash`, and the actual algorithm (accumulate a signed weight per bit across every word's SipHash, then keep the bits that came out positive) is about fifty lines of Rust:

```rust
// native/simhash/src/simhash_algo.rs
pub fn simhash_stream<'w, W>(words: W) -> u64
where
    W: Iterator<Item = &'w str>,
{
    let mut v = [0i32; HASH_BITS];
    for feature in words {
        let feature_hash: u64 = hash_feature(&feature);
        for (i, weight) in v.iter_mut().enumerate() {
            let bit = (feature_hash >> i) & 1;
            if bit == 1 { *weight = weight.saturating_add(1); }
            else        { *weight = weight.saturating_sub(1); }
        }
    }
    let mut simhash: u64 = 0;
    for (i, &weight) in v.iter().enumerate() {
        if weight > 0 { simhash |= 1 << i; }
    }
    simhash
}
```

## The numbers

The benchmark is a separate repo you can run yourself (`mix run benchmarks/simhashing.exs`). This week's run, Apple M3 Max, Elixir 1.19.1 on OTP 28, against a 115-byte input:

```text
Name                             ips        average         memory
holsee/spirit_fingers      1239.54 K        0.81 μs      0.0391 KB
UniversalAvenue/simhash-ex    4.49 K      222.61 μs      533.47 KB
preciz/similarity             4.48 K      223.35 μs      534.63 KB
```

So ~276× faster and ~13,700× lighter than the two pure-Elixir libraries on a small input. Two honesty notes, because a benchmark you can't trust is worse than none.

First, the README still headlines "400-900x faster", which is a stale figure from the old M1 Pro run; the current numbers are 276× at this size. Note to self to update it.

Second, the three libraries aren't computing quite the same thing. spirit_fingers hashes whitespace-split words; the two pure-Elixir ones hash character trigrams by default, which is several times more feature-hashing per call before any language difference is counted. The memory and large-binary gaps are real and enormous (`simhash-ex` errors on a 1.15 MB input and `similarity` climbs past 5 GB of RAM on that same 1.15 MB and takes nearly eight seconds), but the raw speed multiple flatters spirit_fingers a little by comparing unlike work. If you're choosing a SimHash library, the honest story is "the Rust one is the only one that survives megabyte inputs at all", which is true and sufficient, rather than a precise ratio.

## Vendoring, and a ten-minute broken release

The real change in 0.5.x is supply-chain hygiene. Until this release the Rust side depended, by git URL, on Bart Olsthoorn's `simhash` crate: good code (he also wrote `simhash-ex`, the pure-Elixir library I'm fastest against, which I enjoy) but unmaintained. An unmaintained transitive dependency on a hot path, pulled straight from a git ref, is a liability I didn't want anyone inheriting from me. So I vendored the ~50 lines into the tree with MIT attribution and dropped the git dependency; the crate now needs only rustler and siphasher.

One for the war stories, too: I shipped 0.5.0 broken. My explicit package file list included `native/simhash/Cargo.toml` but not `native/simhash/.cargo/config.toml`, the file carrying the macOS `-undefined dynamic_lookup` link flags. Without it, anyone on a Mac who added the package got ``calling `cargo metadata` failed`` and a NIF that wouldn't link. 0.5.0 was the current release for ten minutes and twenty-three seconds before 0.5.1 fixed it. (The same fix caught that the tarball had been shipping the whole `target/` directory: 73 MB, down to 36 KB once the file list was honest.)

## Keeping a NIF alive across Rustler versions

The tax on a foreign-function boundary is that three things (the Elixir side, the Rust toolchain, and Rustler in between) each move on their own schedule, and the library is only as current as the slowest of them. Most of the maintenance over seven years is just riding those upgrades: Rust 2018, then rustler 0.21, then 0.37; Elixir 1.14, then 1.19; each step re-learning how Rustler wants the crate declared.

A small example of the kind of thing you keep an eye on: a NIF that can chew through a megabyte document should be flagged as CPU-bound so it lands on one of the BEAM's dirty schedulers rather than tying up a normal one. How you set that flag changed shape across Rustler versions (it used to be threaded through the export macro, now it's an attribute on the function), so it's exactly the sort of one-liner a big dependency bump can quietly reshape, and one of the things I re-check when I do one.

None of it is hard. It's just the standing cost of living on a boundary, and it's the price of getting Rust's speed from Elixir's comfort.

## For the record

8 hex releases, around 6,600 downloads, 20 stars, 51 commits (50 mine; the other a README clarification from a stranger in 2021 whose commit message, "to avoid further silly questions ;)", I still enjoy). No CHANGELOG. No hand-written Elixir tests either; the suite is doctests, which for a delegation shim to Rust is arguably the right call and definitely the lazy one.

Small numbers, and grand. It does one thing quickly and it hasn't broken in seven years. That was the brief.

## Where to look

- Repo: https://github.com/holsee/spirit_fingers; hex package `spirit_fingers`.
- Benchmarks: https://github.com/holsee/simhash_benchmarks
