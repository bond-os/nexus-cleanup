use ./harness.nu *

run-suite "harness selfcheck" [
    { name: "assert equal passes on equal values", run: {|| assert equal (1 + 1) 2 } }
    { name: "assert error catches a raised error", run: {|| assert error {|| error make {msg: "boom"} } } }
]
