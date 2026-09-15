#!/usr/bin/env bash
# run-one.sh — tek issue kos (Asama 1'in pedagojik yuzu: "yalan soylemeyen rapor").
# Esdegeri: ./run-issues.sh --only <id> ; bu sarmalayici makaledeki adla birebirdir.
exec "$(dirname "$0")/run-issues.sh" --only "${1:?kullanim: run-one.sh <issue-id>}"
