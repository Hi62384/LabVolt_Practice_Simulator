# Practice documentation acceptance

Run from the project root:

```
python tests/acceptance/practice_docs/audit.py
```

This only reads files. It checks exact reviewed source identities/anchors, local documentation links, required scope distinctions, the series-current example's wire topology, and the custom package's coordinate calculation. It accepts snapshot J hashes or the specifically reviewed current Main hashes. Later source changes deliberately require a source-anchor review.

For this internal workstation only, `--external` additionally checks the hashes of existing receipts at the recorded absolute paths. It does not rerun those fixtures. The ordinary command does not require those external files.

Neither mode launches an engine, compiler, renderer, import, network probe, OS probe or process query. A passing documentation audit is not a new gameplay/UI/persistence/native compatibility pass. The precise new guide walkthrough remains source-reviewed until the sole integrator elects to exercise it.
