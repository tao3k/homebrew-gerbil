#!/usr/bin/env bash
set -euo pipefail

image="$RUNNER_TEMP/std-make-one-target"
receipt="$RUNNER_TEMP/v19-staging-std-make-receipt.json"
timings="$RUNNER_TEMP/v19-staging-warm-timings.txt"
: > "$timings"

measure() {
  local label="$1"
  local log="$RUNNER_TEMP/std-make-$label.log"
  set +e
  {
    /usr/bin/time -p env \
      GERBIL_PATH="$image" \
      GERBIL_BUILD_CORES="$GERBIL_BUILD_CORES" \
      GERBIL_BUILD_VERBOSE="$GERBIL_BUILD_VERBOSE" \
      "$GERBIL_PREFIX/bin/gxi" ./build.ss
  } > "$log" 2>&1
  local status=$?
  set -e
  cat "$log"
  MEASURE_SECONDS="$(awk '$1 == "real" { value=$2 } END { print value }' "$log")"
  MEASURE_COMPILE_COUNT="$(grep -c '^\.\.\. compile ' "$log" || true)"
  if [[ -z "$MEASURE_SECONDS" ]]; then
    echo "missing real time for $label" >&2
    return 1
  fi
  if [[ "$status" -ne 0 ]]; then
    return "$status"
  fi
}

rm -rf "$image"
mkdir -p "$image"
measure cold
cold_seconds="$MEASURE_SECONDS"
cold_compile_count="$MEASURE_COMPILE_COUNT"

measure warm1
warm1_seconds="$MEASURE_SECONDS"
warm1_compile_count="$MEASURE_COMPILE_COUNT"
printf '%s\n' "$warm1_seconds" >> "$timings"

measure warm2
warm2_seconds="$MEASURE_SECONDS"
warm2_compile_count="$MEASURE_COMPILE_COUNT"
printf '%s\n' "$warm2_seconds" >> "$timings"

measure warm3
warm3_seconds="$MEASURE_SECONDS"
warm3_compile_count="$MEASURE_COMPILE_COUNT"
printf '%s\n' "$warm3_seconds" >> "$timings"

warm_p50="$(sort -n "$timings" | sed -n '2p')"
warm_compile_count=$((warm1_compile_count + warm2_compile_count + warm3_compile_count))
classification="$(
  awk -v value="$warm_p50" -v budget="$WARM_BUDGET_SECONDS" \
    'BEGIN {
       if (value < 13) print "below-prior-13s-floor";
       else if (value <= 19) print "prior-13-19s-band-persists";
       else if (value <= budget) print "above-prior-band-within-budget";
       else print "warm-budget-exceeded";
     }'
)"

jq -n \
  --arg schema "homebrew-gerbil.v19-staging.std-make-one-target.v1" \
  --arg upstreamRef "$GERBIL_SOURCE_REF" \
  --arg upstreamSha "$UPSTREAM_SHA" \
  --arg runner "${RUNNER_OS}-${RUNNER_ARCH}" \
  --arg classification "$classification" \
  --argjson targetCount 1 \
  --argjson buildCores "$GERBIL_BUILD_CORES" \
  --argjson coldSeconds "$cold_seconds" \
  --argjson coldCompileCount "$cold_compile_count" \
  --argjson warm1Seconds "$warm1_seconds" \
  --argjson warm2Seconds "$warm2_seconds" \
  --argjson warm3Seconds "$warm3_seconds" \
  --argjson warmP50Seconds "$warm_p50" \
  --argjson warmCompileCount "$warm_compile_count" \
  --argjson warmBudgetSeconds "$WARM_BUDGET_SECONDS" \
  '{schema: $schema, upstreamRef: $upstreamRef,
    upstreamSha: $upstreamSha, runner: $runner,
    targetCount: $targetCount, buildCores: $buildCores,
    coldSeconds: $coldSeconds, coldCompileCount: $coldCompileCount,
    warmSeconds: [$warm1Seconds, $warm2Seconds, $warm3Seconds],
    warmP50Seconds: $warmP50Seconds,
    warmCompileCount: $warmCompileCount,
    warmBudgetSeconds: $warmBudgetSeconds,
    classification: $classification}' > "$receipt"

echo "receipt=$receipt" >> "$GITHUB_OUTPUT"
echo "warm_p50=$warm_p50" >> "$GITHUB_OUTPUT"
echo "classification=$classification" >> "$GITHUB_OUTPUT"
{
  echo "### Native std/make one-target result"
  echo "- Target count: 1"
  echo "- Cold: ${cold_seconds}s; compile jobs: ${cold_compile_count}"
  echo "- Warm samples: ${warm1_seconds}s, ${warm2_seconds}s, ${warm3_seconds}s"
  echo "- Warm p50: ${warm_p50}s"
  echo "- Warm compile jobs: ${warm_compile_count}"
  echo "- Classification: \`${classification}\`"
} >> "$GITHUB_STEP_SUMMARY"

if (( warm_compile_count != 0 )); then
  echo "warm runs unexpectedly recompiled targets" >&2
  exit 1
fi
awk -v value="$warm_p50" -v budget="$WARM_BUDGET_SECONDS" \
  'BEGIN { exit(value <= budget ? 0 : 1) }'
