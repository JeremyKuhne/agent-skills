// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Microsoft.VisualStudio.TestTools.UnitTesting;
using SkillEvaluation.Onnx;

namespace SkillEvaluation.Tests;

/// <summary>
///  Tests the exact ownership boundary used for native sessions without constructing a model session.
/// </summary>
[TestClass]
public sealed class GroundingSessionOwnershipTests
{
    /// <summary>
    ///  Verifies every failed validation releases the session and preserves the original exception.
    /// </summary>
    /// <param name="kind">The controlled validation failure.</param>
    [TestMethod]
    [DataRow("contract")]
    [DataRow("io")]
    [DataRow("access")]
    [DataRow("unexpected")]
    public void SessionOwnershipDisposesOnEveryValidationFailure(string kind)
    {
        using RecordingSession session = new();
        Exception expected = kind switch
        {
            "contract" => new EvaluationContractException("Controlled schema validation failure."),
            "io" => new IOException("Controlled post-open asset read failure."),
            "access" => new UnauthorizedAccessException("Controlled post-open asset access failure."),
            "unexpected" => new InvalidOperationException("Controlled metadata failure."),
            _ => throw new ArgumentOutOfRangeException(nameof(kind))
        };

        Exception observed = Assert.Throws<Exception>(() =>
            SessionOwnership.Validate(session, _ => throw expected));

        Assert.AreSame(expected, observed);
        Assert.AreEqual(1, session.DisposedCount);
    }

    /// <summary>
    ///  Verifies a successful validation transfers ownership without prematurely closing the session.
    /// </summary>
    [TestMethod]
    public void SessionOwnershipTransfersSuccessfulSessionToCaller()
    {
        using RecordingSession session = new();
        RecordingSession accepted = SessionOwnership.Validate(session, _ => { });
        Assert.AreSame(session, accepted);
        Assert.AreEqual(0, session.DisposedCount);
        accepted.Dispose();
        Assert.AreEqual(1, session.DisposedCount);
    }

    /// <summary>
    ///  Verifies a missing validation callback cannot abandon an already constructed session.
    /// </summary>
    [TestMethod]
    public void SessionOwnershipDisposesWhenValidationCallbackIsMissing()
    {
        using RecordingSession session = new();
        Assert.ThrowsExactly<ArgumentNullException>(() => SessionOwnership.Validate(session, validate: null));
        Assert.AreEqual(1, session.DisposedCount);
    }

    /// <summary>
    ///  Verifies a missing session is an explicit argument error, not an accepted empty transfer.
    /// </summary>
    [TestMethod]
    public void SessionOwnershipRejectsMissingSession()
    {
        Assert.ThrowsExactly<ArgumentNullException>(() =>
            SessionOwnership.Validate<RecordingSession>(session: null, _ => { }));
    }

}
