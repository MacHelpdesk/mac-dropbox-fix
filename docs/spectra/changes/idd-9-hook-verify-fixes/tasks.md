## 1. Markers

- [x] 1.1 Each skill is announced at most once per session (design: Markers are never deleted by the script). Add the test tagged `spec-example: skill-trigger-hooks / an old marker survives another session`, watch it fail, then remove the cleanup from `skill-hint.sh`. Verified by `/bin/bash tests/test_hooks.sh`.
- [x] 1.2 The marker directory comes from two sources (design: The marker directory has two sources). Add the test tagged `spec-example: skill-trigger-hooks / marker directory sources`, watch it fail, then drop the temporary-directory fallback. Verified by `/bin/bash tests/test_hooks.sh`.

## 2. Recognition

- [x] 2.1 The first batch file command in a Dropbox folder is refused once (design: Verb and path boundaries). Add the new rows of `spec-example: skill-trigger-hooks / commands and decisions`, watch them fail, then change `hasVerb` and `namesDropbox` in `hint.js`. Verified by `/bin/bash tests/test_hooks.sh`.
- [x] 2.2 A session already using a skill is left alone (design: Running the script is a command-position match). Add the test tagged `spec-example: skill-trigger-hooks / script name as an argument`, watch it fail, then change `bashVerdict`. Verified by `/bin/bash tests/test_hooks.sh`.
- [x] 2.3 Only decoded prompt, command and cwd fields are matched (design: Escaped input skips the prefilter). Add the two escaped rows to `spec-example: skill-trigger-hooks / fields that do not count` and watch them fail. Verified by `/bin/bash tests/test_hooks.sh` after 2.4.
- [x] 2.4 Input without the word dropbox starts no second process (design: Escaped input skips the prefilter). Change the rows of `spec-example: skill-trigger-hooks / osascript invocations counted by a stub`, then let `\u` pass the prefilter. Make the test home a fixed string so the count rows do not depend on the temporary path. Verified by `/bin/bash tests/test_hooks.sh`.

## 3. Documents

- [x] 3.1 The plugin states that it runs hooks (design: The refusal reason keeps its last clause). Extend the test tagged `spec-example: skill-trigger-hooks / disclosure strings` for the manifest wording, watch it fail, then update the manifest description, README (cost inside a Dropbox working directory, misjudgement cases, disabling the plugin, markers kept), CLAUDE.md and CHANGELOG. Verified by all five test scripts, `/bin/bash scripts/check-privacy.sh` and `claude plugin validate plugin` passing.
