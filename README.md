
WARNING: Spoilers for Void Stranger ahead!

---

A program that uses BFS to explore the state space of b053 for brand solutions.
Focused on proving (un)reachability of certain brands burdenless: <https://voidstranger.miraheze.org/wiki/Brand>.
Current implementation is based on <https://www.snellman.net/blog/archive/2018-07-23-optimizing-breadth-first-search/>

Requires `zig` 0.16.
Run with: `zig run bfs_move.zig -O ReleaseFast`

---

### Performance

Running commit `b6552f6` under the following conditions:
- Pruning (unchanged from the commit):
  - Minumum tiles at least as many as Tan's brand (21, when not including the tile under the egg)
  - Position never any of 0,3,4,5,10,11,16,29,34
    (corresponding to never entering the X tiles in the following diagram, though they may still be removed by the rod)
    ```
    X....X
    ......
    ......
    X....X
    X....X
    XX..XX
    ```
- Hardware:
  - Macbook with Apple M4 Pro CPU and 24GB RAM

A full exploration of the thusly-pruned state space ran in about **14.5** hours of wall-clock time,
reaching a depth of 199 moves and visiting a total of 14,437,812,425 unique states
(requiring 26 GB of compressed state data, as well as 14.4GB of uncompressed parent pointers),
using about 62 GB total RAM / working set size (including effects of OS compression)
and writing a total of about **7 TB** to disk (as swap) over the entire run.

Past the initial stages, time is vastly dominated by read/write/copy/swap caused by the merge process.

No solution for Tan's brand was found.

