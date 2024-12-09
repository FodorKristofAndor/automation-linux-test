#!/bin/bash

# Function to parse NUnit XML and generate JUnit XML
convert_nunit_to_junit() {
    local nunit_file="$1"
    local junit_file="$2"

    if [[ ! -f "$nunit_file" ]]; then
        echo "Error: The specified NUnit file does not exist: $nunit_file"
        exit 1
    fi

    echo "Converting NUnit XML ($nunit_file) to JUnit XML ($junit_file)..."

    # Temporary file for processing
    temp_junit=$(mktemp)

    # Start creating the JUnit XML
    echo '<?xml version="1.0" encoding="UTF-8"?>' > "$temp_junit"
    echo '<testsuites>' >> "$temp_junit"

    # Group test cases by classname and test name
    declare -A test_cases
    while IFS= read -r test_case; do
        # Extract attributes
        name=$(xmlstarlet sel -t -v "@name" <<< "$test_case")
        classname=$(xmlstarlet sel -t -v "@classname" <<< "$test_case" | sed 's/^LMIAutomation\.//')
        classname=${classname:-"Unknown.Class"} # Fallback to "Unknown.Class" if empty
        duration=$(xmlstarlet sel -t -v "@duration" <<< "$test_case")
        result=$(xmlstarlet sel -t -v "@result" <<< "$test_case")

        # Generate a unique key for grouping
        key="${classname}|${name}"

        # Initialize data if not present
        if [[ -z "${test_cases[$key]}" ]]; then
            test_cases["$key"]="classname=$classname;name=$name;time=0;failures=();retry=0"
        fi

        # Increment the retry count and duration
        current_time=$(awk -F';' -v k="time" '{for (i=1;i<=NF;i++) if ($i ~ k) print substr($i, index($i, "=")+1)}' <<< "${test_cases[$key]}")
        new_time=$(echo "$current_time + $duration" | bc)
        test_cases["$key"]=$(sed "s/time=[^;]*/time=$new_time/" <<< "${test_cases[$key]}")

        # Add failure information if the test failed
        if [[ "$result" == "Failed" ]]; then
            failure_message=$(xmlstarlet sel -t -v "failure/message" <<< "$test_case")
            stack_trace=$(xmlstarlet sel -t -v "failure/stack-trace" <<< "$test_case")
            test_cases["$key"]=$(sed -E "s/failures=\(\)/failures=(${failure_message//$'\n'/\\n}|${stack_trace//$'\n'/\\n})/" <<< "${test_cases[$key]}")
        fi

        # Increment retry count
        current_retry=$(awk -F';' -v k="retry" '{for (i=1;i<=NF;i++) if ($i ~ k) print substr($i, index($i, "=")+1)}' <<< "${test_cases[$key]}")
        test_cases["$key"]=$(sed "s/retry=[^;]*/retry=$((current_retry + 1))/" <<< "${test_cases[$key]}")
    done < <(xmlstarlet sel -t -c "//test-case" "$nunit_file")

    # Build the JUnit XML structure
    for key in "${!test_cases[@]}"; do
        # Parse the stored data
        classname=$(awk -F';' -v k="classname" '{for (i=1;i<=NF;i++) if ($i ~ k) print substr($i, index($i, "=")+1)}' <<< "${test_cases[$key]}")
        name=$(awk -F';' -v k="name" '{for (i=1;i<=NF;i++) if ($i ~ k) print substr($i, index($i, "=")+1)}' <<< "${test_cases[$key]}")
        time=$(awk -F';' -v k="time" '{for (i=1;i<=NF;i++) if ($i ~ k) print substr($i, index($i, "=")+1)}' <<< "${test_cases[$key]}")
        retries=$(awk -F';' -v k="retry" '{for (i=1;i<=NF;i++) if ($i ~ k) print substr($i, index($i, "=")+1)}' <<< "${test_cases[$key]}")

        failures=$(awk -F';' -v k="failures" '{for (i=1;i<=NF;i++) if ($i ~ k) print substr($i, index($i, "=")+1)}' <<< "${test_cases[$key]}")

        # Determine if the test passed
        if [[ "$retries" -lt 4 || "$failures" == "()" ]]; then
            failures=""
        fi

        # Write the test case
        echo "  <testsuite name=\"$classname\" tests=\"1\" failures=\"$([[ -n "$failures" ]] && echo 1 || echo 0)\" time=\"$time\">" >> "$temp_junit"
        echo "    <testcase name=\"$name\" classname=\"$classname\" time=\"$time\">" >> "$temp_junit"
        if [[ -n "$failures" ]]; then
            echo "      <failure message=\"${failures}\"/>" >> "$temp_junit"
        fi
        echo "    </testcase>" >> "$temp_junit"
        echo "  </testsuite>" >> "$temp_junit"
    done

    echo '</testsuites>' >> "$temp_junit"

    # Save the result
    mv "$temp_junit" "$junit_file"
    echo "Converted NUnit results saved to $junit_file"
}

# Validate input
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <nunit_file> <junit_file>"
    exit 1
fi

nunit_file="$1"
junit_file="$2"

convert_nunit_to_junit "$nunit_file" "$junit_file"
