// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;

if (args.Length == 0)
{
    Console.Error.WriteLine("A process-control mode is required.");
    return 3;
}

switch (args[0])
{
    case "exit-with-json":
        Console.Out.WriteLine("""{"schemaVersion":1}""");
        Console.Error.WriteLine("Controlled child failure.");
        return 7;
    case "sleep":
        Thread.Sleep(TimeSpan.FromSeconds(30));
        return 0;
    case "arguments":
        Console.Out.WriteLine(JsonSerializer.Serialize(args[1..]));
        return 0;
    case "rescore":
        int scenarioIndex = Array.IndexOf(args, "--scenario");
        if (scenarioIndex < 0 || scenarioIndex + 1 >= args.Length)
        {
            Console.Error.WriteLine("A scenario is required for the semantic process control.");
            return 3;
        }

        string mode = Path.GetFileNameWithoutExtension(args[scenarioIndex + 1]);
        switch (mode)
        {
            case "empty-summary":
                return 0;
            case "malformed-summary":
                Console.Out.WriteLine("{ malformed summary");
                return 0;
            case "null-summary":
                Console.Out.WriteLine("null");
                return 0;
            case "missing-fields":
                Console.Out.WriteLine("{}");
                return 0;
        }

        if (!int.TryParse(mode, out int exitCode) || exitCode is not (0 or 1 or 2 or 3 or 7))
        {
            Console.Error.WriteLine("Unknown semantic process-control mode.");
            return 3;
        }

        Console.Out.WriteLine("""{"runCount":1,"usefulPassedCount":0,"pendingCount":1,"usefulFailedCount":0,"safetyFailureCount":0,"infrastructureFailureCount":0}""");
        if (exitCode == 7)
        {
            Console.Error.WriteLine("Controlled unexpected exit.");
        }

        return exitCode;
    default:
        Console.Error.WriteLine("Unknown process-control mode.");
        return 3;
}
