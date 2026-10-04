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
    default:
        Console.Error.WriteLine("Unknown process-control mode.");
        return 3;
}
