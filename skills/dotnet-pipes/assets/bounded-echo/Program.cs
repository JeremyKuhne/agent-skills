using System.Text;

namespace DotNetPipes.Sample;

internal static class Program
{
    private static async Task<int> Main(string[] arguments)
    {
        if (arguments.Length < 2)
        {
            WriteUsage();
            return 1;
        }

        string mode = arguments[0];
        string pipeName = arguments[1];

        if (string.Equals(mode, "server", StringComparison.OrdinalIgnoreCase)
            && arguments.Length is 2 or 3)
        {
            return await RunServerAsync(pipeName, arguments).ConfigureAwait(false);
        }

        if (string.Equals(mode, "client", StringComparison.OrdinalIgnoreCase) && arguments.Length == 3)
        {
            return await RunClientAsync(pipeName, arguments[2]).ConfigureAwait(false);
        }

        WriteUsage();
        return 1;
    }

    private static async Task<int> RunServerAsync(string pipeName, string[] arguments)
    {
        int maxConcurrentClients = 4;
        if (arguments.Length == 3
            && (!int.TryParse(arguments[2], out maxConcurrentClients) || maxConcurrentClients is < 1 or > 254))
        {
            Console.Error.WriteLine("The maximum client count must be between 1 and 254.");
            return 1;
        }

        using CancellationTokenSource shutdown = new();

        void CancelOnControlC(object? sender, ConsoleCancelEventArgs eventArguments)
        {
            eventArguments.Cancel = true;
            shutdown.Cancel();
        }

        Console.CancelKeyPress += CancelOnControlC;
        try
        {
            Console.WriteLine($"Listening on '{pipeName}' for up to {maxConcurrentClients} clients. Press Ctrl+C to stop.");
            await NamedPipeEchoServer.RunAsync(pipeName, maxConcurrentClients, shutdown.Token).ConfigureAwait(false);
            return 0;
        }
        finally
        {
            Console.CancelKeyPress -= CancelOnControlC;
        }
    }

    private static async Task<int> RunClientAsync(string pipeName, string message)
    {
        byte[] payload = Encoding.UTF8.GetBytes(message);
        byte[] response = await NamedPipeEchoClient.EchoAsync(
            pipeName,
            payload,
            TimeSpan.FromSeconds(5),
            CancellationToken.None).ConfigureAwait(false);

        Console.WriteLine(Encoding.UTF8.GetString(response));
        return 0;
    }

    private static void WriteUsage()
    {
        Console.Error.WriteLine("Usage:");
        Console.Error.WriteLine("  BoundedPipeEcho server <pipe-name> [max-clients]");
        Console.Error.WriteLine("  BoundedPipeEcho client <pipe-name> <message>");
        Console.Error.WriteLine();
        Console.Error.WriteLine("max-clients defaults to 4 and must be between 1 and 254.");
    }
}