#!/usr/bin/env bash
set -euo pipefail

package_count="${SCALE_PACKAGE_COUNT:-8}"
modules_per_package="${SCALE_MODULES_PER_PACKAGE:-16}"
module_count=$((package_count * modules_per_package))
source_root="$RUNNER_TEMP/std-make-scale-source"
image="$RUNNER_TEMP/std-make-scale-image"
receipt="$RUNNER_TEMP/v19-staging-std-make-scale-receipt.json"
timings="$RUNNER_TEMP/v19-staging-scale-warm-timings.txt"

rm -rf "$source_root" "$image"
mkdir -p "$source_root/packages" "$source_root/app" "$image"
: > "$timings"
app_imports=""
app_expansions=""

for package_index in $(seq 1 "$package_count"); do
  package_id="pkg$(printf '%02d' "$package_index")"
  package_name="std-make-scale/$package_id"
  package_dir="$source_root/packages/$package_id"
  mkdir -p "$package_dir"
  printf '(package: %s)\n' "$package_name" > "$package_dir/gerbil.pkg"
  package_imports=""
  package_exports=""
  package_spec=""

  for module_index in $(seq 1 "$modules_per_package"); do
    module_id="leaf$(printf '%03d' "$module_index")"
    binding_prefix="${package_id}-${module_id}"
    cat > "$package_dir/$module_id.ss" <<EOF_MODULE
(export ${binding_prefix}-rule ${binding_prefix}-value)
(defrules ${binding_prefix}-rule ()
  ((_ value)
   (list '${package_id}/${module_id} value)))
(def ${binding_prefix}-value
  (${binding_prefix}-rule $module_index))
EOF_MODULE
    package_imports="$package_imports :${package_name}/${module_id}"
    package_exports="$package_exports (import: :${package_name}/${module_id})"
    package_spec="$package_spec \"$module_id\""
    app_expansions="$app_expansions (${binding_prefix}-rule ${module_index})"
  done

  printf '(import%s)\n(export%s)\n' \
    "$package_imports" "$package_exports" > "$package_dir/interface.ss"
  cat > "$package_dir/build.ss" <<EOF_PACKAGE_BUILD
#!/usr/bin/env gxi
(import :std/build-script)
(defbuild-script '($package_spec "interface"))
EOF_PACKAGE_BUILD
  app_imports="$app_imports :${package_name}/interface"
done

printf '(package: std-make-scale/app)\n' > "$source_root/app/gerbil.pkg"
{
  printf '(import%s)\n' "$app_imports"
  printf '(export scale-probe)\n'
  printf '(def scale-probe (list%s))\n' "$app_expansions"
} > "$source_root/app/probe.ss"
cat > "$source_root/app/build-one.ss" <<'EOF_APP_BUILD'
#!/usr/bin/env gxi
(import :std/build-script)
(defbuild-script '("probe"))
EOF_APP_BUILD
cat > "$source_root/seed.sh" <<'EOF_SEED'
#!/usr/bin/env bash
set -euo pipefail
for package_dir in "$SCALE_SOURCE_ROOT"/packages/pkg*; do
  (cd "$package_dir" && "$GERBIL_PREFIX/bin/gxi" ./build.ss)
done
cd "$SCALE_SOURCE_ROOT/app"
"$GERBIL_PREFIX/bin/gxi" ./build-one.ss
EOF_SEED
chmod +x "$source_root/seed.sh"

measure() {
  local label="$1"
  shift
  local log="$RUNNER_TEMP/std-make-scale-$label.log"
  set +e
  {
    /usr/bin/time -p env \
      GERBIL_PATH="$image" \
      GERBIL_BUILD_CORES="$GERBIL_BUILD_CORES" \
      GERBIL_BUILD_VERBOSE="$GERBIL_BUILD_VERBOSE" \
      SCALE_SOURCE_ROOT="$source_root" \
      "$@"
  } > "$log" 2>&1
  local status=$?
  set -e
  cat "$log"
  MEASURE_SECONDS="$(awk '$1 == "real" { value=$2 } END { print value }' "$log")"
  MEASURE_COMPILE_COUNT="$(grep -c '^\.\.\. compile ' "$log" || true)"
  if [[ -z "$MEASURE_SECONDS" ]]; then
    echo "missing real time for scale $label" >&2
    return 1
  fi
  if [[ "$status" -ne 0 ]]; then
    return "$status"
  fi
}

measure seed bash "$source_root/seed.sh"
seed_seconds="$MEASURE_SECONDS"
seed_compile_count="$MEASURE_COMPILE_COUNT"

cd "$source_root/app"
touch probe.ss
measure cold "$GERBIL_PREFIX/bin/gxi" ./build-one.ss
cold_seconds="$MEASURE_SECONDS"
cold_compile_count="$MEASURE_COMPILE_COUNT"

measure warm1 "$GERBIL_PREFIX/bin/gxi" ./build-one.ss
warm1_seconds="$MEASURE_SECONDS"
warm1_compile_count="$MEASURE_COMPILE_COUNT"
printf '%s\n' "$warm1_seconds" >> "$timings"
measure warm2 "$GERBIL_PREFIX/bin/gxi" ./build-one.ss
warm2_seconds="$MEASURE_SECONDS"
warm2_compile_count="$MEASURE_COMPILE_COUNT"
printf '%s\n' "$warm2_seconds" >> "$timings"
measure warm3 "$GERBIL_PREFIX/bin/gxi" ./build-one.ss
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
  --arg schema "homebrew-gerbil.v19-staging.std-make-package-macro-one-target.v1" \
  --arg upstreamRef "$GERBIL_SOURCE_REF" \
  --arg upstreamSha "$UPSTREAM_SHA" \
  --arg runner "${RUNNER_OS}-${RUNNER_ARCH}" \
  --arg classification "$classification" \
  --argjson targetCount 1 \
  --argjson packageCount "$package_count" \
  --argjson macroModuleCount "$module_count" \
  --argjson buildCores "$GERBIL_BUILD_CORES" \
  --argjson seedSeconds "$seed_seconds" \
  --argjson seedCompileCount "$seed_compile_count" \
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
    targetCount: $targetCount, packageCount: $packageCount,
    macroModuleCount: $macroModuleCount, buildCores: $buildCores,
    seedSeconds: $seedSeconds, seedCompileCount: $seedCompileCount,
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
  echo "### Native std/make package/macro one-target result"
  echo "- Target count: 1; packages: ${package_count}; macro modules: ${module_count}"
  echo "- Seed closure: ${seed_seconds}s; compile jobs: ${seed_compile_count}"
  echo "- Cold aggregate: ${cold_seconds}s; compile jobs: ${cold_compile_count}"
  echo "- Warm samples: ${warm1_seconds}s, ${warm2_seconds}s, ${warm3_seconds}s"
  echo "- Warm p50: ${warm_p50}s"
  echo "- Warm compile jobs: ${warm_compile_count}"
  echo "- Classification: \`${classification}\`"
} >> "$GITHUB_STEP_SUMMARY"

if (( cold_compile_count != 1 )); then
  echo "scale cold run did not compile exactly one aggregate target" >&2
  exit 1
fi
if (( warm_compile_count != 0 )); then
  echo "scale warm runs unexpectedly recompiled targets" >&2
  exit 1
fi
awk -v value="$warm_p50" -v budget="$WARM_BUDGET_SECONDS" \
  'BEGIN { exit(value <= budget ? 0 : 1) }'
