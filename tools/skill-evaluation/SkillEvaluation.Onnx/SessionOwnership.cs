// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation.Onnx;

/// <summary>
///  Owns a newly constructed session until post-construction validation transfers it to the caller.
/// </summary>
internal static class SessionOwnership
{
    /// <summary>
    ///  Validates one newly owned disposable session before returning it.
    /// </summary>
    /// <typeparam name="T">The disposable session type.</typeparam>
    /// <param name="session">The new session whose ownership is being transferred.</param>
    /// <param name="validate">The required post-construction validation.</param>
    /// <returns>The successfully validated session, now owned by the caller.</returns>
    internal static T Validate<T>(T? session, Action<T>? validate) where T : class, IDisposable
    {
        ArgumentNullException.ThrowIfNull(session);
        bool accepted = false;
        try
        {
            ArgumentNullException.ThrowIfNull(validate);
            validate(session);
            accepted = true;
            return session;
        }
        finally
        {
            if (!accepted)
            {
                session.Dispose();
            }
        }
    }
}
