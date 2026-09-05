using System.IO.Pipes;

namespace DotNetPipes.TestSupport;

public static class AnonymousPipeChild
{
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
            .ConfigureAwait(false);
        if (receivedLength > MaxCaptureLength)
        {
            Console.Error.WriteLine("Anonymous test input exceeds the capture limit.");
            return 2;
        }

        Console.Write(Convert.ToBase64String(received, 0, receivedLength));
        return 0;
    }
}