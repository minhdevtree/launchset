import Foundation
import LaunchSetCore

let args = Array(CommandLine.arguments.dropFirst())
if let first = args.first, ["help", "-h", "--help"].contains(first) {
    print(CLI.usage)
    exit(0)
}

let response: CLIResponse
do {
    response = try CLI.send(CLIRequest(args: args))
} catch {
    FileHandle.standardError.write(Data("""
    LaunchSet isn't running, so there is nothing to talk to (\(error)).
    Start it with: open -b \(Blocklist.ownBundleID)

    """.utf8))
    exit(1)
}

if response.exitCode == 0 {
    print(response.output)
} else {
    FileHandle.standardError.write(Data((response.output + "\n").utf8))
}
exit(response.exitCode)
