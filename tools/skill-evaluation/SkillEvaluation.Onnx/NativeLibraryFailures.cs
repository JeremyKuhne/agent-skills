// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation.Onnx;

/// <summary>
///  Identifies known native-loader causes without hiding unrelated initialization defects.
/// </summary>
public static class NativeLibraryFailures
{
    /// <summary>
    ///  Finds a known loader failure within direct or nested CLR type-initialization exceptions.
    /// </summary>
    /// <param name="error">The observed runtime exception.</param>
    /// <returns>The known loader cause, or null for an unrelated exception.</returns>
    public static Exception? FindCause(Exception? error)
    {
        ArgumentNullException.ThrowIfNull(error);
        while (error is TypeInitializationException { InnerException: Exception cause })
        {
            error = cause;
        }

        return error is DllNotFoundException or BadImageFormatException or EntryPointNotFoundException
            ? error
            : null;
    }
}
