# Pull Request

Thanks for sending this. Please fill in everything below — empty
sections will be sent back.

## What this PR does

<!-- One short paragraph. -->

## Why

<!-- What problem does it solve? Link the issue or design doc. -->

## How to test

<!-- Exact commands a reviewer should run. For bash changes, include
     `make lint` output. For docs changes, mention both EN and ZH. -->

```bash
# reviewer's checklist
```

## Checklist

- [ ] I ran `bin/devbox doctor` and it is green
- [ ] I tested both `CN_MIRROR=1` and `CN_MIRROR=0` paths if I touched
      `setup/provision.sh` or any download URL
- [ ] I ran `make lint` and it is clean (or explained why I can't)
- [ ] I updated both English and Chinese docs if I added a new section
      (English first, then mirror — see CONTRIBUTING.md)
- [ ] I did not commit any secrets, tokens, or `node_modules/`
- [ ] I did not bypass any deny-list entry in `.claude/settings.json`
- [ ] If this is a yolo-safety-affecting change, I described the threat
      model impact in the PR body and flagged a maintainer for review

## Screenshots / logs (if relevant)

<!-- paste here -->

## Related issues

<!-- `closes #123`, `fixes #456`, or `relates to #789` -->
