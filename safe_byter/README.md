# Safe byter 

Reads one byte at some address **SAFELY**

## Usage

```
cargo build
cargo test -- --test-threads 1
```

Output:
```
running 4 tests
test tests::external_handler_not_triggered_on_successful_read ... ok
test tests::external_handler_triggered_on_unrelated_fault ... ok
test tests::int_to_ptr ... ok
test tests::real_ptr ... ok

test result: ok. 4 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s

   Doc-tests safe_byter

running 0 tests

test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```