Run full test suite and verify build.

1. Server tests: `cd Server && swift test`
2. Client tests: `cd Client && swift test`
3. If failures, analyze and report
4. If pass, run `./Scripts/build-release.sh`
5. Report summary with pass/fail counts
