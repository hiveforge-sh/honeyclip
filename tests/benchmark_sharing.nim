## Benchmark Sharing System
##
## Allows users to opt-in to sharing benchmark results with the project
## to help gather real-world performance data across different platforms
## and hardware configurations.
##
## Privacy-first: All sharing is OPT-IN and requires explicit consent.

import std/[json, strformat, os, osproc, httpclient, times, strutils, tables]
import ../src/log

type
  SystemInfo* = object
    ## Anonymous system information for benchmark context
    os*: string              # "linux", "macos", "windows"
    osVersion*: string       # e.g., "Ubuntu 24.04", "macOS 14.2"
    arch*: string            # "x86_64", "aarch64"
    cpuModel*: string        # e.g., "Intel Core i7-9700K"
    cpuCores*: int           # Physical cores
    cpuThreads*: int         # Logical cores (with hyperthreading)
    ramGB*: int              # Total RAM in GB
    compiler*: string        # e.g., "nim-2.2.6 / gcc-13.2.0"
    
  BenchmarkReport* = object
    ## Complete benchmark report for sharing
    version*: string         # honeyclip version
    timestamp*: string       # When benchmark was run
    system*: SystemInfo      # Hardware/software info
    results*: JsonNode       # Benchmark results
    settings*: JsonNode      # Build settings (codecs enabled, etc.)

const
  BenchmarkReportVersion = "1.0"
  ShareEndpoint = "https://api.github.com/repos/hiveforge-sh/honeyclip/issues"  # Or dedicated endpoint

# Detect system information (anonymously)
proc detectSystemInfo(): SystemInfo =
  result = SystemInfo()
  
  # OS detection
  when defined(linux):
    result.os = "linux"
  elif defined(macos):
    result.os = "macos"
  elif defined(windows):
    result.os = "windows"
  else:
    result.os = "unknown"
  
  # Architecture
  when defined(amd64) or defined(x86_64):
    result.arch = "x86_64"
  elif defined(arm64) or defined(aarch64):
    result.arch = "aarch64"
  elif defined(i386):
    result.arch = "i386"
  else:
    result.arch = "unknown"
  
  # OS version (platform-specific)
  when defined(macos):
    try:
      let (output, _) = execCmdEx("sw_vers -productVersion")
      result.osVersion = "macOS " & output.strip()
    except:
      result.osVersion = "macOS (unknown version)"
  
  when defined(linux):
    try:
      # Try lsb_release first
      let (output, code) = execCmdEx("lsb_release -ds 2>/dev/null")
      if code == 0:
        result.osVersion = output.strip()
      else:
        # Fallback to /etc/os-release
        if fileExists("/etc/os-release"):
          let osRelease = readFile("/etc/os-release")
          for line in osRelease.splitLines():
            if line.startsWith("PRETTY_NAME="):
              result.osVersion = line.split("=")[1].strip(chars = {'"'})
              break
    except:
      result.osVersion = "Linux (unknown distribution)"
  
  when defined(windows):
    try:
      let (output, _) = execCmdEx("ver")
      result.osVersion = output.strip()
    except:
      result.osVersion = "Windows (unknown version)"
  
  # CPU detection (platform-specific)
  when defined(linux):
    try:
      let cpuinfo = readFile("/proc/cpuinfo")
      for line in cpuinfo.splitLines():
        if line.startsWith("model name"):
          result.cpuModel = line.split(":")[1].strip()
          break
        if line.startsWith("cpu cores"):
          result.cpuCores = parseInt(line.split(":")[1].strip())
    except:
      result.cpuModel = "Unknown CPU"
  
  when defined(macos):
    try:
      let (model, _) = execCmdEx("sysctl -n machdep.cpu.brand_string")
      result.cpuModel = model.strip()
      let (cores, _) = execCmdEx("sysctl -n hw.physicalcpu")
      result.cpuCores = parseInt(cores.strip())
      let (threads, _) = execCmdEx("sysctl -n hw.logicalcpu")
      result.cpuThreads = parseInt(threads.strip())
    except:
      result.cpuModel = "Unknown CPU"
  
  when defined(windows):
    try:
      let (model, _) = execCmdEx("wmic cpu get name /value")
      for line in model.splitLines():
        if line.startsWith("Name="):
          result.cpuModel = line.split("=")[1].strip()
          break
    except:
      result.cpuModel = "Unknown CPU"
  
  # RAM detection (platform-specific)
  when defined(linux):
    try:
      let meminfo = readFile("/proc/meminfo")
      for line in meminfo.splitLines():
        if line.startsWith("MemTotal:"):
          let kb = parseInt(line.split()[1])
          result.ramGB = (kb / 1024 / 1024).int + 1  # Round up
          break
    except:
      result.ramGB = 0
  
  when defined(macos):
    try:
      let (mem, _) = execCmdEx("sysctl -n hw.memsize")
      let bytes = parseBiggestInt(mem.strip())
      result.ramGB = (bytes / 1024 / 1024 / 1024).int
    except:
      result.ramGB = 0
  
  when defined(windows):
    try:
      let (mem, _) = execCmdEx("wmic ComputerSystem get TotalPhysicalMemory /value")
      for line in mem.splitLines():
        if line.startsWith("TotalPhysicalMemory="):
          let bytes = parseBiggestInt(line.split("=")[1].strip())
          result.ramGB = (bytes / 1024 / 1024 / 1024).int
          break
    except:
      result.ramGB = 0
  
  # Compiler info
  try:
    let (nimVer, _) = execCmdEx("nim --version")
    let nimLine = nimVer.splitLines()[0]
    result.compiler = nimLine.strip()
  except:
    result.compiler = "Unknown Nim version"

# Create shareable benchmark report
proc createBenchmarkReport*(results: JsonNode, buildSettings: JsonNode = nil): BenchmarkReport =
  result = BenchmarkReport(
    version: BenchmarkReportVersion,
    timestamp: $now(),
    system: detectSystemInfo(),
    results: results,
    settings: if buildSettings.isNil: newJObject() else: buildSettings
  )

# Export report to JSON file
proc exportReportToFile*(report: BenchmarkReport, path: string) =
  var json = newJObject()
  json["version"] = %report.version
  json["timestamp"] = %report.timestamp
  
  var sysJson = newJObject()
  sysJson["os"] = %report.system.os
  sysJson["osVersion"] = %report.system.osVersion
  sysJson["arch"] = %report.system.arch
  sysJson["cpuModel"] = %report.system.cpuModel
  sysJson["cpuCores"] = %report.system.cpuCores
  sysJson["cpuThreads"] = %report.system.cpuThreads
  sysJson["ramGB"] = %report.system.ramGB
  sysJson["compiler"] = %report.system.compiler
  
  json["system"] = sysJson
  json["results"] = report.results
  json["settings"] = report.settings
  
  writeFile(path, json.pretty())
  echo &"Benchmark report exported to: {path}"

# Display report summary for user review
proc displayReportSummary*(report: BenchmarkReport) =
  echo "\n" & "=".repeat(60)
  echo "Benchmark Report Summary"
  echo "=".repeat(60)
  echo &"Version:      {report.version}"
  echo &"Timestamp:    {report.timestamp}"
  echo ""
  echo "System Information:"
  echo &"  OS:         {report.system.osVersion} ({report.system.arch})"
  echo &"  CPU:        {report.system.cpuModel}"
  echo &"  Cores:      {report.system.cpuCores} physical, {report.system.cpuThreads} logical"
  echo &"  RAM:        {report.system.ramGB}GB"
  echo &"  Compiler:   {report.system.compiler}"
  echo ""
  echo "Benchmark Results:"
  for result in report.results:
    let name = result["name"].getStr()
    let duration = result["durationMs"].getInt()
    echo &"  {name}: {duration}ms"
  echo "=".repeat(60)
  echo ""

# Prompt user for consent to share
proc promptForConsent*(): bool =
  echo "\n" & "=".repeat(60)
  echo "Share Benchmark Results"
  echo "=".repeat(60)
  echo ""
  echo "Would you like to share your benchmark results with the project?"
  echo ""
  echo "This helps us:"
  echo "  • Understand real-world performance across different hardware"
  echo "  • Optimize for common configurations"
  echo "  • Validate performance claims"
  echo ""
  echo "What will be shared:"
  echo "  • Benchmark timings (ms)"
  echo "  • OS and architecture (e.g., 'macOS 14.2 x86_64')"
  echo "  • CPU model and core count"
  echo "  • RAM amount"
  echo "  • Compiler version"
  echo ""
  echo "What will NOT be shared:"
  echo "  • Your name, email, or any personal information"
  echo "  • IP address or location"
  echo "  • File paths or data from your system"
  echo "  • Anything else not listed above"
  echo ""
  echo "You can review the full report before sharing."
  echo "=".repeat(60)
  
  stdout.write("Share results? (yes/no): ")
  stdout.flushFile()
  
  let response = stdin.readLine().strip().toLowerAscii()
  return response in ["yes", "y"]

# Share report (GitHub issue or dedicated endpoint)
proc shareReport*(report: BenchmarkReport, shareMethod: string = "file"): bool =
  case shareMethod
  of "file":
    # Save to shareable file that user can upload manually
    let reportPath = "benchmark_report_" & now().format("yyyyMMddHHmmss") & ".json"
    exportReportToFile(report, reportPath)
    
    echo ""
    echo "Benchmark report saved!"
    echo ""
    echo "To share with the project:"
    echo &"  1. Review the file: {reportPath}"
    echo "  2. Create a GitHub issue: https://github.com/hiveforge-sh/honeyclip/issues/new"
    echo "  3. Title: 'Benchmark Results: [Your CPU/OS]'"
    echo "  4. Paste the contents of the report file"
    echo ""
    echo "Thank you for contributing!"
    
    return true
  
  of "github":
    # Automatic GitHub issue creation (requires token)
    # TODO: Implement when we have a dedicated GitHub App
    echo "Automatic sharing not yet implemented"
    echo "Please use the 'file' method for now"
    return false
  
  else:
    echo &"Unknown sharing method: {shareMethod}"
    return false
