param (
    [string]$nunitFile,
    [string]$junitFile
)

# Validate input
if (-not (Test-Path $nunitFile)) {
    Write-Error "The specified NUnit file does not exist: $nunitFile"
    exit 1
}

# Load the NUnit XML document
$nunitXml = New-Object System.Xml.XmlDocument
$nunitXml.Load($nunitFile)

# Create a new JUnit XML document
$junitXml = New-Object System.Xml.XmlDocument
$root = $junitXml.CreateElement("testsuites")
$junitXml.AppendChild($root)

# Group test cases by classname and test name
$groupedTestCases = @{}

foreach ($testCase in $nunitXml.SelectNodes("//test-case")) {
    $name = $testCase.getAttribute("name")
    $classname = $testCase.getAttribute("classname") -replace '^LMIAutomation\.', '' # Remove 'LMIAutomation.' prefix

    # Ensure classname is not empty
    if ([string]::IsNullOrEmpty($classname)) {
        $classname = "Unknown.Class"
    }

    # Unique key for grouping test cases
    $key = "$classname|$name"

    if (-not $groupedTestCases.ContainsKey($key)) {
        $groupedTestCases[$key] = @{
            Name = $name
            Classname = $classname
            Time = 0.0
            Failures = @()
        }
    }

    # Add the test case's duration
    $duration = [double]($testCase.getAttribute("duration") -as [double])
    $groupedTestCases[$key]["Time"] += $duration

    # Add failure details if the test failed
    if ($testCase.getAttribute("result") -eq "Failed") {
        $failureMessage = $testCase.SelectSingleNode("failure/message")?.InnerText
        $stackTrace = $testCase.SelectSingleNode("failure/stack-trace")?.InnerText
        $groupedTestCases[$key]["Failures"] += @{
            Message = $failureMessage
            StackTrace = $stackTrace
        }
    }
}

# Create a testsuite element for each classname
$testsuites = $groupedTestCases.Values | Group-Object -Property Classname
foreach ($suiteGroup in $testsuites) {
    $classname = $suiteGroup.Name
    $testCases = $suiteGroup.Group

    # Create a testsuite element
    $testsuite = $junitXml.CreateElement("testsuite")
    $testsuite.SetAttribute("name", $classname)
    $testsuite.SetAttribute("tests", $testCases.Count)
    $testsuite.SetAttribute("failures", ($testCases | Where-Object { $_.Failures.Count -gt 0 }).Count)
    $testsuite.SetAttribute("time", [string]::Format("{0:0.000}", ($testCases | Measure-Object -Property Time -Sum).Sum))
    $root.AppendChild($testsuite)

    # Add test cases to the testsuite
    foreach ($testGroup in $testCases) {
        $junitTestCase = $junitXml.CreateElement("testcase")
        $junitTestCase.SetAttribute("name", $testGroup.Name)
        $junitTestCase.SetAttribute("classname", $classname)
        $junitTestCase.SetAttribute("time", [string]::Format("{0:0.000}", $testGroup.Time))

        # Merge all failure messages and stack traces into a single failure element
        if ($testGroup.Failures.Count -gt 0) {
            $mergedFailureMessage = ($testGroup.Failures | ForEach-Object { $_.Message }) -join "`n------------------END OF STACKTRACE------------------`n"
            $mergedStackTrace = ($testGroup.Failures | ForEach-Object { $_.StackTrace }) -join "`n------------------END OF STACKTRACE------------------`n"

            $failureElement = $junitXml.CreateElement("failure")
            $failureElement.SetAttribute("message", $mergedFailureMessage)
            $failureElement.InnerText = $mergedStackTrace
            $junitTestCase.AppendChild($failureElement)
        }

        $testsuite.AppendChild($junitTestCase)
    }
}

# Save the JUnit XML document
$junitXml.Save($junitFile)
Write-Host "Converted NUnit results saved to $junitFile"
