## 1. Running the script

- [x] 1.1 A session already using a skill is left alone (design: A variable run is matched within one command; Three token forms for the script path). Add the new rows of `spec-example: skill-trigger-hooks / script name as an argument` and the test tagged `spec-example: skill-trigger-hooks / variable run before a copy`, watch them fail, then rewrite `ownScript` in `hint.js`. Verified by `/bin/bash tests/test_hooks.sh`.

## 2. Markers and matching

- [x] 2.1 Each skill is announced at most once per session (design: Marker creation refuses any existing path). Add the test tagged `spec-example: skill-trigger-hooks / marker path is a symbolic link`, watch it fail, then check for an existing path in `mark()`. Verified by `/bin/bash tests/test_hooks.sh`.
- [x] 2.2 The first batch file command in a Dropbox folder is refused once. Add the row with a working directory outside the home directory to `spec-example: skill-trigger-hooks / commands and decisions`, watch it fail, then change `insideDropbox`. Verified by `/bin/bash tests/test_hooks.sh`.
- [x] 2.3 A stuck-Dropbox prompt gets one hint naming dropbox-fix. Add the real-estate row to `spec-example: skill-trigger-hooks / prompts and hints`, watch it fail, then narrow the term in `hint.js`. Verified by `/bin/bash tests/test_hooks.sh`.
- [x] 2.4 Input without the word dropbox starts no second process (design: The escape exception is narrowed; No program before the prefilter). Add the literal backslash-u row to `spec-example: skill-trigger-hooks / osascript invocations counted by a stub`, watch it fail, then narrow the exception and read the input with builtins. Verified by `/bin/bash tests/test_hooks.sh`.

## 3. Documents and real runs

- [x] 3.1 The plugin states that it runs hooks (design: Run counts). Extend the test tagged `spec-example: skill-trigger-hooks / disclosure strings` for CLAUDE.md and both skill files, watch it fail, then update CLAUDE.md, both SKILL.md files, README and CHANGELOG; run each scenario once with `claude -p --plugin-dir plugin` at the final code and write the counts into the verification tables. Verified by all five test scripts, `/bin/bash scripts/check-privacy.sh` and `claude plugin validate plugin` passing.
