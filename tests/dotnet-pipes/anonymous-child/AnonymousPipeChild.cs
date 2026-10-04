// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.IO.Pipes;

namespace DotNetPipes.TestSupport;

/// <summary>
///  Captures bounded input from an inherited anonymous-pipe client handle.
/// </summary>
public static class AnonymousPipeChild
{
    /// <summary>
    ///  The maximum number of input bytes accepted by the test child.
    /// </summary>
    public const int MaxCaptureLength = 64 * 1024;

    private static async Task<int> Main(string[] arguments)
    {
        if (arguments.Length != 1)
        {
            Console.Error.WriteLine("Expected one inherited client handle.");
            return 1;
        }

        await using AnonymousPipeClientStream client = new(PipeDirection.In, arguments[0]);
        byte[] received = new byte[MaxCaptureLength + 1];
        int receivedLength = await client.ReadAtLeastAsync(received, received.Length, throwOnEndOfStream: false)
            .ConfigureAwait(continueOnCapturedContext: false);

        if (receivedLength > MaxCaptureLength)
        {
            Console.Error.WriteLine("Anonymous test input exceeds the capture limit.");
            return 2;
        }

        Console.Write(Convert.ToBase64String(received, 0, receivedLength));
        return 0;
    }
}